import 'dart:async';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';

import '../../../../core/models/peer_identity.dart';
import '../../../../app/di/app_dependencies.dart';
import '../../../../core/utils/logger.dart';
import '../../../../core/utils/timestamp_formatter.dart';
import '../../data/datasources/drift_conversation_data_source.dart';
import '../../data/datasources/drift_read_receipt_data_source.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_message_payload.dart';
import '../../domain/entities/conversation.dart';
import '../../domain/entities/read_receipt.dart';
import '../../domain/usecases/send_message.dart';
import '../../domain/usecases/watch_messages.dart';

typedef RememberPeer = Future<void> Function(PeerIdentity identity);

class ChatController extends ChangeNotifier {
  ChatController({
    required SendMessage sendMessage,
    required WatchMessages watchMessages,
    required PeerIdentity identity,
    required Conversation conversation,
    required DriftConversationDataSource conversationStore,
    required RememberPeer rememberPeer,
    DriftReadReceiptDataSource? readReceiptDataSource,
    Map<String, PeerIdentity>? knownPeers,
  }) : _sendMessage = sendMessage,
       _watchMessages = watchMessages,
       _identity = identity,
       _conversation = conversation,
       _conversationStore = conversationStore,
       _rememberPeer = rememberPeer,
       _readReceiptDataSource = readReceiptDataSource,
       _knownPeers = Map<String, PeerIdentity>.from(
         knownPeers ?? <String, PeerIdentity>{},
       ) {
    final ctorLogger = const Logger('ChatController');
    ctorLogger.info(
      '[ChatController] created instance=$hashCode convo=${_conversation.id}',
    );
  }

  final SendMessage _sendMessage;
  final WatchMessages _watchMessages;
  final PeerIdentity _identity;
  final DriftConversationDataSource _conversationStore;
  final RememberPeer _rememberPeer;
  final DriftReadReceiptDataSource? _readReceiptDataSource;
  Conversation _conversation;
  final Map<String, PeerIdentity> _knownPeers;

  /// Optional callback to show error messages to user
  void Function(String message)? onDownloadError;

  /// Optional callback to show info messages to user
  void Function(String message)? onDownloadInfo;

  /// When this device is a **client**, set this to the gateway IP reported by
  /// `HotspotClientState.hostGatewayIpAddress`.  The file-download logic will
  /// prefer this IP over the host's self-reported `senderHostIp` because the
  /// two can diverge on certain Android versions / OEM skins (e.g. Samsung
  /// Android 16).  The gateway IP is the one the WebSocket already routes
  /// through, so it is always reachable from the client.
  String? hostGatewayOverrideIp;

  final TextEditingController messageFieldController = TextEditingController();

  StreamSubscription<List<ChatMessage>>? _subscription;
  final List<ChatMessageViewModel> _messages = <ChatMessageViewModel>[];
  bool _hasLoadedInitial = false;
  // Track download failures per attachment id
  final Map<String, int> _downloadFailures = <String, int>{};
  // Keep original P2P file info for pending downloads keyed by file id
  final Map<String, Map<String, dynamic>> _pendingFileInfos =
      <String, Map<String, dynamic>>{};
  // Attachments already queued for download (avoid re-triggering on every
  // DB watch emission).
  final Set<String> _downloadingAttachmentIds = <String>{};

  // Read receipt tracking
  StreamSubscription<Map<String, List<ReadReceipt>>>? _readReceiptSubscription;

  /// Map of messageId → list of read receipts (who has seen that message).
  Map<String, List<ReadReceipt>> _readReceipts = <String, List<ReadReceipt>>{};

  /// Callback for sending a read receipt over P2P.
  Future<void> Function(Map<String, dynamic> receiptJson)? onSendReadReceipt;

  List<ChatMessageViewModel> get messages =>
      List<ChatMessageViewModel>.unmodifiable(_messages);

  /// Read receipts indexed by message ID. Each entry contains the list of
  /// users who have seen that message.
  Map<String, List<ReadReceipt>> get readReceipts =>
      Map<String, List<ReadReceipt>>.unmodifiable(_readReceipts);

  /// Read receipts filtered so each reader's avatar appears only on the
  /// **most recent** message they have seen. This produces Messenger-style
  /// behaviour where indicators migrate downward as readers catch up.
  Map<String, List<ReadReceipt>> get latestReadReceipts {
    // Step 1: For each reader, find their latest receipt (by seenAt).
    final latestByReader = <String, ReadReceipt>{};
    for (final receipts in _readReceipts.values) {
      for (final receipt in receipts) {
        final existing = latestByReader[receipt.seenByUserId];
        if (existing == null || receipt.seenAt.isAfter(existing.seenAt)) {
          latestByReader[receipt.seenByUserId] = receipt;
        }
      }
    }

    // Step 2: Rebuild map keyed by messageId with only the "latest" entries.
    final result = <String, List<ReadReceipt>>{};
    for (final receipt in latestByReader.values) {
      result.putIfAbsent(receipt.messageId, () => <ReadReceipt>[]).add(receipt);
    }
    return result;
  }

  /// True until the first DB watch emission has been received for the
  /// current conversation. UI can use this to display a loading state.
  bool get hasLoadedInitial => _hasLoadedInitial;

  String get localPeerId => _identity.id;
  String get localDisplayName => _identity.displayName;
  Conversation get conversation => _conversation;

  set conversation(Conversation value) {
    if (_conversation.id == value.id && _conversation.title == value.title) {
      return;
    }
    _conversation = value;
    // Reset initial-loaded flag when conversation changes and refresh
    // subscription so UI shows a loading state until the first snapshot.
    _hasLoadedInitial = false;
    if (_subscription != null) {
      _subscribeToMessages();
    }
    notifyListeners();
  }

  Future<void> start() async {
    // Always refresh the subscription to ensure latest messages are loaded
    _hasLoadedInitial = false;
    _subscribeToMessages();
    _subscribeToReadReceipts();
  }

  /// Subscribe to read receipt changes from the database.
  void _subscribeToReadReceipts() {
    _readReceiptSubscription?.cancel();
    final ds = _readReceiptDataSource;
    if (ds == null) return;
    _readReceiptSubscription = ds
        .watchReadReceipts(_conversation.id)
        .listen(
          (receipts) {
            _readReceipts = receipts;
            notifyListeners();
          },
          onError: (Object error) {
            const logTag = 'ChatController';
            final logger = const Logger(logTag);
            logger.info(
              '[ChatController:$hashCode] read receipt stream error: $error',
            );
          },
        );
  }

  /// Mark all visible messages in the conversation as seen by the local user.
  /// This persists the receipts to the DB and broadcasts them over P2P.
  Future<void> markMessagesAsSeen() async {
    final ds = _readReceiptDataSource;
    if (ds == null) return;
    if (_messages.isEmpty) return;

    final now = DateTime.now().toUtc();
    // Find the absolute most-recent message (regardless of sender) that
    // we haven't already marked as seen.  Including local messages is
    // intentional — in Messenger-style receipts, when the other party
    // reads the conversation their avatar should appear under YOUR latest
    // sent message.  Skipping local messages would leave the receipt on
    // an earlier remote message, which looks wrong from the sender's view.
    ChatMessageViewModel? latestUnseen;
    for (final m in _messages) {
      final existing = _readReceipts[m.id];
      if (existing != null &&
          existing.any((r) => r.seenByUserId == _identity.id)) {
        continue;
      }
      // _messages is ordered oldest-first, so keep overwriting to get last.
      latestUnseen = m;
    }

    if (latestUnseen == null) return;

    final receipt = ReadReceipt(
      messageId: latestUnseen.id,
      conversationId: _conversation.id,
      seenByUserId: _identity.id,
      seenByDisplayName: _identity.displayName,
      seenByProfileImage: _identity.profileImage,
      seenAt: now,
    );
    await ds.saveReadReceipt(receipt);
    // Broadcast over P2P
    onSendReadReceipt?.call(receipt.toJson());
  }

  /// Handle an incoming read receipt from a remote peer (received via P2P).
  Future<void> receiveReadReceipt(Map<String, dynamic> json) async {
    final ds = _readReceiptDataSource;
    if (ds == null) return;
    try {
      final receipt = ReadReceipt.fromJson(json);
      // Only store receipts for the current conversation.
      if (receipt.conversationId == _conversation.id) {
        await ds.saveReadReceipt(receipt);
      }
    } catch (e) {
      debugPrint('ChatController: Failed to process read receipt: $e');
    }
  }

  void _subscribeToMessages() {
    _subscription?.cancel();
    _subscription =
        _watchMessages(
          WatchMessagesParams(conversationId: _conversation.id),
        ).listen(
          (messages) {
            // mark that we've received the initial snapshot for this convo
            _hasLoadedInitial = true;
            try {
              // Log instance id so we can verify UI/controller instance alignment
              const logTag = 'ChatController';
              final logger = const Logger(logTag);
              logger.info(
                '[ChatController:$hashCode] received ${messages.length} messages for conversation ${_conversation.id}',
              );
              try {
                final ds = AppDependencies.instance.driftChatMessageDataSource;
                if (ds != null) {
                  unawaited(
                    ds.getMessageCount(_conversation.id).then((cnt) {
                      const logTag2 = 'ChatController.debug';
                      final logger2 = const Logger(logTag2);
                      logger2.info(
                        '[ChatController.debug:$hashCode] DB count for convo ${_conversation.id} = $cnt',
                      );
                    }),
                  );
                }
              } catch (_) {}
            } catch (_) {}
            // Build new view models from DB, but preserve any in-memory
            // attachment URIs that were set by a download that hasn't been
            // persisted to DB yet (race between download completion and
            // the next DB watch emission).
            final oldByMsgId = <String, ChatMessageViewModel>{
              for (final m in _messages) m.id: m,
            };

            _messages.clear();
            _messages.addAll(
              messages.map((message) {
                final vm = ChatMessageViewModel.fromEntity(
                  message,
                  localPeerId: _identity.id,
                  localIdentity: _identity,
                  knownPeers: _knownPeers,
                );

                // Merge in-memory attachment URIs that are newer than DB
                final oldVm = oldByMsgId[vm.id];
                if (oldVm != null && oldVm.attachments.isNotEmpty) {
                  for (int i = 0; i < vm.attachments.length; i++) {
                    final dbA = vm.attachments[i];
                    if (dbA.uri.isEmpty) {
                      // Check if in-memory version has a downloaded URI
                      final oldA = oldVm.attachments
                          .where((a) => a.id == dbA.id)
                          .firstOrNull;
                      if (oldA != null && oldA.uri.isNotEmpty) {
                        vm.attachments[i] = dbA.copyWith(uri: oldA.uri);
                      }
                    }
                  }
                }
                return vm;
              }),
            );
            notifyListeners();

            // Auto-download only recent attachments that have transport info
            // but no local file yet. This avoids download storms when a
            // client joins and receives large history sync batches.
            _checkPendingAttachmentDownloads();
          },
          onError: (Object error, StackTrace? stack) {
            const logTag = 'ChatController';
            final logger = const Logger(logTag);
            logger.info(
              '[ChatController:$hashCode] stream error for convo ${_conversation.id}: $error',
            );
          },
        );
  }

  /// Scan loaded messages for undownloaded attachments that have transport
  /// info (senderHostIp + senderPort) and trigger downloads.
  ///
  /// Intentionally limited to recent messages to avoid mass-downloading old
  /// history attachments when a device joins an existing, long-running room.
  void _checkPendingAttachmentDownloads() {
    final now = DateTime.now().toUtc();
    const recentWindow = Duration(minutes: 3);

    for (final vm in _messages) {
      final messageAge = now.difference(vm.sentAt.toUtc());
      if (messageAge > recentWindow) {
        continue;
      }

      for (final att in vm.attachments) {
        if (att.uri.isEmpty &&
            att.senderHostIp != null &&
            att.senderPort != null &&
            !_downloadingAttachmentIds.contains(att.id) &&
            (_downloadFailures[att.id] ?? 0) < 3) {
          _downloadingAttachmentIds.add(att.id);
          _pendingFileInfos[att.id] = att.toJson();
          debugPrint(
            'ChatController: Auto-downloading history attachment '
            '${att.filename} from http://${att.senderHostIp}:${att.senderPort}/file?id=${att.id}',
          );
          unawaited(_attemptDownloadForAttachment(vm.id, att));
        }
      }
    }
  }

  Future<ChatMessage?> sendLocalMessage(String rawContent) async {
    return sendLocalMessageWithAttachments(rawContent, attachments: null);
  }

  Future<ChatMessage?> sendLocalMessageWithAttachments(
    String rawContent, {
    List<ChatAttachment>? attachments,
    bool attachmentsAreExternal = false,
  }) async {
    final content = rawContent.trim();
    if (content.isEmpty && (attachments == null || attachments.isEmpty)) {
      return null;
    }
    messageFieldController.clear();

    // Optimistically add the message to the local in-memory list so the UI
    // updates immediately without waiting for the DB watch stream. The
    // DB remains the source of truth; when the watch stream emits it will
    // replace this list (no duplication because items are keyed by id).
    final optimistic = ChatMessage(
      id: _generateOptimisticId(),
      conversationId: _conversation.id,
      senderId: _identity.id,
      sender: _identity.displayName,
      content: content,
      sentAt: DateTime.now().toUtc(),
      attachments: attachments ?? const [],
    );
    _messages.insert(
      0,
      ChatMessageViewModel.fromEntity(
        optimistic,
        localPeerId: _identity.id,
        localIdentity: _identity,
        knownPeers: _knownPeers,
      ),
    );
    notifyListeners();

    final storedMessage = await _sendMessage(
      SendMessageParams(
        conversationId: _conversation.id,
        senderId: _identity.id,
        sender: _identity.displayName,
        content: content,
        attachments: attachments,
        attachmentsAreExternal: attachmentsAreExternal,
      ),
    );

    unawaited(
      _conversationStore.ensureConversationExists(
        id: _conversation.id,
        title: _conversation.title,
      ),
    );
    return storedMessage;
  }

  String _generateOptimisticId() =>
      'local_${DateTime.now().microsecondsSinceEpoch}';

  Future<void> receiveMessage(ChatMessage message) async {
    if (message.senderId == _identity.id) {
      return;
    }

    final senderName = message.sender.trim();
    if (senderName.isNotEmpty) {
      final existingIdentity = _knownPeers[message.senderId];
      if (existingIdentity == null) {
        // First time seeing this peer — create a minimal identity.
        final newIdentity = PeerIdentity(
          id: message.senderId,
          displayName: senderName,
        );
        _knownPeers[message.senderId] = newIdentity;
        unawaited(_rememberPeer(newIdentity));
      } else if (existingIdentity.displayName != senderName) {
        // Display name changed — update it but keep the rest of the identity.
        final updated = existingIdentity.copyWith(displayName: senderName);
        _knownPeers[message.senderId] = updated;
        unawaited(_rememberPeer(updated));
      }
      // Otherwise the identity we already have is richer — keep it.
    }

    // Save attachments with empty URI so the DB has attachment metadata
    // (filename, mimeType, etc.) even before the file is downloaded.
    // Strip senderHostIp/senderPort from persisted attachments (transport-only).
    final persistAttachments = message.attachments.map((a) {
      return ChatAttachment(
        id: a.id,
        filename: a.filename,
        mimeType: a.mimeType,
        sizeBytes: a.sizeBytes,
        uri: '', // empty until download completes
      );
    }).toList();

    debugPrint(
      'ChatController: receiveMessage saving ${persistAttachments.length} attachment(s) to DB for msg ${message.id}',
    );

    await _sendMessage(
      SendMessageParams(
        id: message.id,
        conversationId: message.conversationId,
        senderId: message.senderId,
        sender: message.sender,
        content: message.content,
        sentAt: message.sentAt,
        attachments: persistAttachments.isNotEmpty ? persistAttachments : null,
        attachmentsAreExternal: true,
      ),
    );
  }

  Future<void> receivePayload(ChatMessagePayload payload) async {
    final conversationRecord = await _conversationStore
        .ensureConversationExists(
          id: payload.conversationId,
          title: payload.conversationTitle,
        );
    conversation = conversationRecord;

    // Extract and remember sender identity, merging defensively so that
    // incomplete payloads (e.g. history sync) don't erase richer data we
    // already have.
    final senderIdentity = payload.getSenderIdentity();
    final existingIdentity = _knownPeers[senderIdentity.id];
    if (existingIdentity == null) {
      _knownPeers[senderIdentity.id] = senderIdentity;
      unawaited(_rememberPeer(senderIdentity));
    } else {
      // Merge: prefer incoming non-null values, but keep existing non-null
      // values when the incoming payload omits them.
      final merged = PeerIdentity(
        id: senderIdentity.id,
        displayName: senderIdentity.displayName.isNotEmpty
            ? senderIdentity.displayName
            : existingIdentity.displayName,
        name: senderIdentity.name ?? existingIdentity.name,
        role: senderIdentity.role != UserRole.other
            ? senderIdentity.role
            : existingIdentity.role,
        groupName: senderIdentity.groupName ?? existingIdentity.groupName,
        profileImage:
            senderIdentity.profileImage ?? existingIdentity.profileImage,
      );
      if (merged.displayName != existingIdentity.displayName ||
          merged.name != existingIdentity.name ||
          merged.role != existingIdentity.role ||
          merged.groupName != existingIdentity.groupName ||
          merged.profileImage != existingIdentity.profileImage) {
        _knownPeers[senderIdentity.id] = merged;
        unawaited(_rememberPeer(merged));
      }
    }

    final chatMsg = payload.toChatMessage();
    await receiveMessage(chatMsg);

    // If message contains attachments with transport info, attempt automatic download
    if (chatMsg.attachments.isNotEmpty) {
      debugPrint(
        'ChatController: Received message with ${chatMsg.attachments.length} attachment(s)',
      );
      for (final attachment in chatMsg.attachments) {
        debugPrint(
          'ChatController: Attachment ${attachment.filename} - IP: ${attachment.senderHostIp}, Port: ${attachment.senderPort}, URI: ${attachment.uri}, ID: ${attachment.id}',
        );
        if (attachment.senderHostIp != null &&
            attachment.senderPort != null &&
            attachment.uri.isEmpty) {
          // Store attachment object for retry attempts
          _pendingFileInfos[attachment.id] = attachment.toJson();
          debugPrint(
            'ChatController: Starting download for ${attachment.filename} from http://${attachment.senderHostIp}:${attachment.senderPort}/file?id=${attachment.id}',
          );
          unawaited(_attemptDownloadForAttachment(chatMsg.id, attachment));
        } else {
          debugPrint(
            'ChatController: Skipping download - missing info or already has URI',
          );
        }
      }
    }
  }

  Map<String, int> get downloadFailures =>
      Map<String, int>.unmodifiable(_downloadFailures);

  /// Public request to (re)attempt downloading an attachment for a message.
  Future<void> requestAttachmentDownload(
    String messageId,
    ChatAttachment attachment,
  ) async {
    // Reset failure count so UI shows the downloading spinner during retry
    _downloadFailures.remove(attachment.id);
    notifyListeners();

    if (attachment.senderHostIp == null || attachment.senderPort == null) {
      // Try to retrieve transport info from pending map
      final pendingInfo = _pendingFileInfos[attachment.id];
      if (pendingInfo != null) {
        final hostIp = pendingInfo['senderHostIp'] as String?;
        final port = pendingInfo['senderPort'] as int?;
        if (hostIp != null && port != null) {
          final enriched = attachment.copyWith(
            senderHostIp: hostIp,
            senderPort: port,
          );
          await _attemptDownloadForAttachment(messageId, enriched);
          return;
        }
      }
      return;
    }
    await _attemptDownloadForAttachment(messageId, attachment);
  }

  Future<void> _attemptDownloadForAttachment(
    String messageId,
    ChatAttachment attachment,
  ) async {
    final fileId = attachment.id;
    final hostIp = attachment.senderHostIp;
    final port = attachment.senderPort;
    final name = attachment.filename;
    if (hostIp == null || port == null) {
      debugPrint(
        'ChatController: Cannot download attachment $fileId - missing host IP or port',
      );
      return;
    }

    // Prefer the gateway IP that the WebSocket successfully routes through.
    // On some Android versions / OEM skins the host's self-reported IP
    // (from NetworkInterface enumeration) differs from the gateway IP the
    // client actually reaches via DHCP / LinkProperties routes.
    final effectiveIp =
        (hostGatewayOverrideIp != null && hostGatewayOverrideIp!.isNotEmpty)
        ? hostGatewayOverrideIp!
        : hostIp;

    if (effectiveIp != hostIp) {
      debugPrint(
        'ChatController: Overriding senderHostIp $hostIp → gateway $effectiveIp',
      );
    }

    final uri = Uri.parse(
      'http://$effectiveIp:$port/file?id=${Uri.encodeComponent(fileId)}',
    );

    debugPrint(
      'ChatController: Attempting to download attachment $name from $uri',
    );

    onDownloadInfo?.call('Downloading $name...');

    // Prepare output path up-front so partial files can be cleaned up.
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/attachments');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);
    final localPath = '${outDir.path}/$fileId-${Uri.encodeComponent(name)}';

    int attempts = 0;
    const maxAttempts = 3;

    // Build a list of URIs to try. The primary URI uses the effective IP
    // (gateway override when available).  If that differs from the host's
    // self-reported IP, append a fallback URI with the original IP so we
    // cover both cases.
    final urisToTry = <Uri>[uri];
    if (effectiveIp != hostIp) {
      urisToTry.add(
        Uri.parse(
          'http://$hostIp:$port/file?id=${Uri.encodeComponent(fileId)}',
        ),
      );
    }

    for (final downloadUri in urisToTry) {
      attempts = 0;
      while (attempts < maxAttempts) {
        attempts++;
        final client = http.Client();
        try {
          // Use a streamed request so large files (videos) are written to disk
          // chunk-by-chunk instead of being buffered entirely in memory.
          final request = http.Request('GET', downloadUri);
          final streamedResponse = await client
              .send(request)
              .timeout(const Duration(seconds: 15));

          if (streamedResponse.statusCode == 200) {
            final outFile = File(localPath);
            final sink = outFile.openWrite();
            int bytesReceived = 0;

            try {
              await for (final chunk in streamedResponse.stream.timeout(
                // Allow up to 30s of inactivity between chunks; the overall
                // download has no hard cap so large videos can complete.
                const Duration(seconds: 30),
              )) {
                sink.add(chunk);
                bytesReceived += chunk.length;
              }
              await sink.flush();
              await sink.close();
            } catch (e) {
              await sink.close();
              // Clean up partial file on stream failure
              if (outFile.existsSync()) outFile.deleteSync();
              rethrow;
            }

            debugPrint(
              'ChatController: Successfully downloaded $bytesReceived bytes for $name',
            );
            debugPrint('ChatController: Saved attachment to $localPath');

            // Update failure count and persist attachment URI in stored message
            _downloadFailures.remove(fileId);

            // Find message view model and update attachments list locally
            final idx = _messages.indexWhere((m) => m.id == messageId);
            List<ChatAttachment>? updatedAttachments;
            if (idx != -1) {
              final vm = _messages[idx];
              updatedAttachments = vm.attachments.map((a) {
                if (a.id == fileId) {
                  debugPrint(
                    'ChatController: Updating attachment ${a.id} with local URI: $localPath',
                  );
                  return a.copyWith(uri: localPath);
                }
                return a;
              }).toList();

              // Create new ViewModel instance to trigger rebuild
              _messages[idx] = ChatMessageViewModel(
                id: vm.id,
                conversationId: vm.conversationId,
                senderId: vm.senderId,
                sender: vm.sender,
                content: vm.content,
                sentAt: vm.sentAt,
                attachments: updatedAttachments,
                isLocal: vm.isLocal,
                senderIdentity: vm.senderIdentity,
              );

              debugPrint(
                'ChatController: Updated message ${vm.id} with new attachment list, notifying listeners',
              );
              notifyListeners();

              // Persist updated attachment URI to DB.
              // Preserve the original sentAt so message ordering stays
              // chronological — without this, the timestamp defaults to
              // DateTime.now() and large-file downloads shift to the end.
              await _sendMessage(
                SendMessageParams(
                  id: messageId,
                  conversationId: _conversation.id,
                  senderId: vmOrDefaultSenderId(messageId),
                  sender: vmOrDefaultSenderName(messageId),
                  content: vmOrDefaultContent(messageId),
                  sentAt: vm.sentAt,
                  attachments: updatedAttachments,
                  attachmentsAreExternal: true,
                ),
              );
            }

            return;
          } else {
            // treat as failure and retry
            debugPrint(
              'ChatController: Download failed for $name - status ${streamedResponse.statusCode}',
            );
            _downloadFailures[fileId] = (_downloadFailures[fileId] ?? 0) + 1;
          }
        } catch (e) {
          debugPrint(
            'ChatController: Download error for $name (attempt $attempts/$maxAttempts): $e',
          );
          _downloadFailures[fileId] = (_downloadFailures[fileId] ?? 0) + 1;
        } finally {
          client.close();
        }

        // small backoff
        await Future<void>.delayed(Duration(milliseconds: 400 * attempts));
      }

      // If there are more URIs to try (fallback IP), log and continue the
      // outer for-loop instead of giving up immediately.
      if (downloadUri != urisToTry.last) {
        debugPrint(
          'ChatController: Retrying $name with fallback URI ${urisToTry.last}',
        );
        continue;
      }

      debugPrint(
        'ChatController: Failed to download $name after exhausting all IPs',
      );
      onDownloadError?.call('Failed to download $name. Tap retry button.');
      // After max attempts, leave failure count which UI can use to show manual refresh
      notifyListeners(); // Refresh UI to show retry button
      return;
    } // end for (urisToTry)
  }

  String vmOrDefaultSenderId(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) return _messages[idx].senderId;
    return _identity.id;
  }

  String vmOrDefaultSenderName(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) return _messages[idx].sender;
    return _identity.displayName;
  }

  String vmOrDefaultContent(String messageId) {
    final idx = _messages.indexWhere((m) => m.id == messageId);
    if (idx != -1) return _messages[idx].content;
    return '';
  }

  @override
  void dispose() {
    messageFieldController.dispose();
    // Cancel the subscription so the broadcast StreamController in
    // ChatMessageQueryService can detect 0 listeners and fire onCancel
    // (which defers teardown via Future.delayed, giving a new controller
    // time to re-subscribe). Pausing instead of cancelling keeps a phantom
    // listener alive, preventing onListen from firing for the next
    // subscriber — which causes the "Loading messages..." hang.
    _subscription?.cancel();
    _subscription = null;
    _readReceiptSubscription?.cancel();
    _readReceiptSubscription = null;
    super.dispose();
  }
}

class ChatMessageViewModel {
  ChatMessageViewModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sender,
    required this.content,
    required this.sentAt,
    required this.attachments,
    required this.isLocal,
    required this.senderIdentity,
  });

  factory ChatMessageViewModel.fromEntity(
    ChatMessage entity, {
    required String localPeerId,
    required PeerIdentity localIdentity,
    required Map<String, PeerIdentity> knownPeers,
  }) {
    final isLocal = entity.senderId == localPeerId;
    final PeerIdentity senderIdentity;

    if (isLocal) {
      senderIdentity = localIdentity;
    } else {
      final knownIdentity = knownPeers[entity.senderId];
      senderIdentity =
          knownIdentity ??
          PeerIdentity(id: entity.senderId, displayName: entity.sender);
    }

    return ChatMessageViewModel(
      id: entity.id,
      conversationId: entity.conversationId,
      senderId: entity.senderId,
      sender: senderIdentity.displayName,
      content: entity.content,
      sentAt: entity.sentAt,
      attachments: List<ChatAttachment>.from(entity.attachments),
      isLocal: isLocal,
      senderIdentity: senderIdentity,
    );
  }

  final String id;
  final String conversationId;
  final String senderId;
  final String sender;
  final String content;
  final DateTime sentAt;
  final List<ChatAttachment> attachments;
  final bool isLocal;
  final PeerIdentity senderIdentity;

  String get sentAtFormatted {
    return TimestampFormatter.format(
      sentAt,
      format: AppDependencies.instance.timeFormat,
    );
  }

  String get displaySender => isLocal ? 'You' : sender;
}
