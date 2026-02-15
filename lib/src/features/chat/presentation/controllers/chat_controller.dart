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
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../domain/entities/chat_message_payload.dart';
import '../../domain/entities/conversation.dart';
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
    Map<String, PeerIdentity>? knownPeers,
  }) : _sendMessage = sendMessage,
       _watchMessages = watchMessages,
       _identity = identity,
       _conversation = conversation,
       _conversationStore = conversationStore,
       _rememberPeer = rememberPeer,
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
  Conversation _conversation;
  final Map<String, PeerIdentity> _knownPeers;

  /// Optional callback to show error messages to user
  void Function(String message)? onDownloadError;
  
  /// Optional callback to show info messages to user
  void Function(String message)? onDownloadInfo;

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

  List<ChatMessageViewModel> get messages =>
      List<ChatMessageViewModel>.unmodifiable(_messages);

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
  }

  void _subscribeToMessages() {
    _subscription?.cancel();
    _subscription =
        _watchMessages(
          WatchMessagesParams(conversationId: _conversation.id),
        ).listen((messages) {
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

          // Auto-download any attachments that have transport info but no
          // local file yet (e.g. from history sync).  This runs on every
          // DB watch emission but _downloadingAttachmentIds prevents
          // duplicate download attempts.
          _checkPendingAttachmentDownloads();
        }, onError: (Object error, StackTrace? stack) {
          const logTag = 'ChatController';
          final logger = const Logger(logTag);
          logger.info(
            '[ChatController:$hashCode] stream error for convo ${_conversation.id}: $error',
          );
        });
  }

  /// Scan loaded messages for undownloaded attachments that have transport
  /// info (senderHostIp + senderPort) and trigger downloads.  This covers
  /// history-synced messages whose download events were emitted before
  /// ChatPage subscribed to the incoming-messages broadcast stream.
  void _checkPendingAttachmentDownloads() {
    for (final vm in _messages) {
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

    final uri = Uri.parse(
      'http://$hostIp:$port/file?id=${Uri.encodeComponent(fileId)}',
    );

    debugPrint(
      'ChatController: Attempting to download attachment $name from $uri',
    );
    
    onDownloadInfo?.call('Downloading $name...');

    int attempts = 0;
    const maxAttempts = 3;
    while (attempts < maxAttempts) {
      attempts++;
      try {
        final resp = await http.get(uri).timeout(const Duration(seconds: 10));
        if (resp.statusCode == 200) {
          debugPrint(
            'ChatController: Successfully downloaded ${resp.bodyBytes.length} bytes for $name',
          );
          // write to permanent app storage
          final dir = await getApplicationDocumentsDirectory();
          final outDir = Directory('${dir.path}/attachments');
          if (!outDir.existsSync()) outDir.createSync(recursive: true);
          final localPath =
              '${outDir.path}/$fileId-${Uri.encodeComponent(name)}';
          final outFile = File(localPath);
          await outFile.writeAsBytes(resp.bodyBytes, flush: true);

          debugPrint(
            'ChatController: Saved attachment to $localPath',
          );

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
            
            // Persist updated attachment URI to DB
            await _sendMessage(
              SendMessageParams(
                id: messageId,
                conversationId: _conversation.id,
                senderId: vmOrDefaultSenderId(messageId),
                sender: vmOrDefaultSenderName(messageId),
                content: vmOrDefaultContent(messageId),
                attachments: updatedAttachments,
                attachmentsAreExternal: true,
              ),
            );
          }

          return;
        } else {
          // treat as failure and retry
          debugPrint(
            'ChatController: Download failed for $name - status ${resp.statusCode}',
          );
          _downloadFailures[fileId] = (_downloadFailures[fileId] ?? 0) + 1;
        }
      } catch (e) {
        debugPrint(
          'ChatController: Download error for $name (attempt $attempts/$maxAttempts): $e',
        );
        _downloadFailures[fileId] = (_downloadFailures[fileId] ?? 0) + 1;
      }

      // small backoff
      await Future<void>.delayed(Duration(milliseconds: 400 * attempts));
    }

    debugPrint(
      'ChatController: Failed to download $name after $maxAttempts attempts',
    );
    onDownloadError?.call('Failed to download $name. Tap retry button.');
    // After max attempts, leave failure count which UI can use to show manual refresh
    notifyListeners(); // Refresh UI to show retry button
    return;
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
