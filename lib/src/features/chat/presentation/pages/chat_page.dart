import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../../../../app/di/app_dependencies.dart';
import '../../../../core/models/join_request.dart';
import '../../../../core/models/peer_identity.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../../../../core/utils/logger.dart';
import '../../../p2p/data/services/p2p_service.dart';
import '../../../p2p/presentation/controllers/p2p_session_controller.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../../p2p/presentation/widgets/latency_diagnostics_sheet.dart';
import '../../domain/entities/chat_message_payload.dart';
import '../../domain/entities/conversation.dart';
import '../controllers/chat_controller.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../widgets/inline_video_player.dart';
import '../widgets/read_receipt_indicator.dart';

class ChatPage extends StatefulWidget {
  const ChatPage({
    super.key,
    required this.conversation,
    this.controller,
    this.p2pController,
    this.testPeerIdentity,
  });

  static const routeName = '/chat/session';

  final Conversation conversation;
  final ChatController? controller;
  final P2pSessionController? p2pController;
  final PeerIdentity? testPeerIdentity;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ChatController _controller;
  late final bool _ownsController;
  late final P2pSessionController _p2pController;
  late final bool _ownsP2pController;
  StreamSubscription<ChatMessagePayload>? _incomingSubscription;
  StreamSubscription<Map<String, dynamic>>? _readReceiptSubscription;
  final ScrollController _messageScrollController = ScrollController();
  final FocusNode _composerFocusNode = FocusNode();
  int _lastMessageCount = 0;
  Timer? _markSeenTimer;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        AppDependencies.instance.createChatController(
          conversation: widget.conversation,
        );
    _ownsController = widget.controller == null;
    _p2pController =
        widget.p2pController ??
        AppDependencies.instance.createP2pSessionController();
    _ownsP2pController = widget.p2pController == null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      // Preserve existing privacy settings so the announcement isn't
      // overwritten with isPrivate=false when navigating from the
      // conversation picker that already set them.
      _p2pController.setActiveConversation(
        widget.conversation,
        isPrivate: _p2pController.activeConversationIsPrivate,
        passwordHash: _p2pController.activeConversationPasswordHash,
        requiresApproval: _p2pController.activeConversationRequiresApproval,
      );
    });
    unawaited(_controller.start());
    _lastMessageCount = _controller.messages.length;
    _controller.addListener(_handleMessagesChanged);
    _composerFocusNode.addListener(_handleComposerFocusChange);

    // Set up download error callback to show user-visible messages
    _controller.onDownloadError = (String message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 60, left: 16, right: 16),
            action: SnackBarAction(
              label: 'OK',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    };

    _controller.onDownloadInfo = (String message) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            behavior: SnackBarBehavior.floating,
            margin: const EdgeInsets.only(bottom: 60, left: 16, right: 16),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    };

    _incomingSubscription = _p2pController.incomingMessages.listen((
      payload,
    ) async {
      if (!mounted) {
        return;
      }
      await _controller.receivePayload(payload);
    });

    // Keep the chat controller's gateway‑IP override in sync with the P2P
    // client state so that file downloads use the known-reachable IP.
    _p2pController.addListener(_syncGatewayOverride);
    _syncGatewayOverride(); // set initial value

    // Wire up read receipt P2P transport.
    _controller.onSendReadReceipt = (Map<String, dynamic> receiptJson) async {
      await _p2pController.sendReadReceipt(receiptJson);
    };
    _readReceiptSubscription = _p2pController.incomingReadReceipts.listen((
      json,
    ) async {
      if (!mounted) return;
      await _controller.receiveReadReceipt(json);
    });

    // Mark currently visible messages as seen on first load.
    _controller.addListener(_markMessagesAsSeenOnce);
  }

  /// Push the P2P client-state gateway IP into the [ChatController] so that
  /// file downloads use the known-reachable IP instead of the host's
  /// self-reported IP (which can differ on certain Android versions).
  void _syncGatewayOverride() {
    if (_p2pController.role == P2pSessionRole.client) {
      _controller.hostGatewayOverrideIp =
          _p2pController.clientState?.hostGatewayIpAddress;
    } else {
      _controller.hostGatewayOverrideIp = null;
    }
  }

  /// One-shot listener: once messages are loaded, mark them seen and remove
  /// itself. Subsequent "seen" updates happen via [_handleMessagesChanged].
  void _markMessagesAsSeenOnce() {
    if (_controller.hasLoadedInitial && _controller.messages.isNotEmpty) {
      _controller.removeListener(_markMessagesAsSeenOnce);
      _debouncedMarkSeen();
    }
  }

  /// Debounced wrapper around [ChatController.markMessagesAsSeen].
  ///
  /// During rapid message arrival (e.g. history sync after a device joins)
  /// many calls pile up quickly. Each one would broadcast a receipt for an
  /// intermediate message; earlier broadcasts may be lost in WebSocket
  /// congestion, leaving the remote side stuck on a stale receipt.
  ///
  /// By debouncing, we wait until the message list stabilises and then
  /// broadcast **one** receipt for the absolute latest message.
  void _debouncedMarkSeen() {
    _markSeenTimer?.cancel();
    _markSeenTimer = Timer(const Duration(milliseconds: 600), () {
      unawaited(_controller.markMessagesAsSeen());
    });
  }

  @override
  void dispose() {
    _markSeenTimer?.cancel();
    _incomingSubscription?.cancel();
    _p2pController.removeListener(_syncGatewayOverride);
    _readReceiptSubscription?.cancel();
    _controller.removeListener(_handleMessagesChanged);
    _composerFocusNode.removeListener(_handleComposerFocusChange);
    _composerFocusNode.unfocus();
    _composerFocusNode.dispose();
    if (_ownsController) {
      _controller.dispose();
    }
    if (_ownsP2pController) {
      _p2pController.dispose();
    }
    _messageScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Text(_controller.conversation.title),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.speed_outlined),
            tooltip: 'Latency diagnostics',
            onPressed: _showLatencyDiagnostics,
          ),
          // Debug: print DB message counts and recent message IDs
          if (AppDependencies.instance.debugMessagesEnabled)
            IconButton(
              icon: const Icon(Icons.bug_report),
              tooltip: 'Debug messages',
              onPressed: () async {
                try {
                  final logger = const Logger('ChatPage.debug');
                  final ds =
                      AppDependencies.instance.driftChatMessageDataSource;
                  if (ds == null) {
                    logger.info('driftChatMessageDataSource is null');
                    return;
                  }
                  final count = await ds.getMessageCount(
                    _controller.conversation.id,
                  );
                  // Fetch recent messages before 'now + 1 day' to include all
                  final recent = await ds.getMessagesBefore(
                    _controller.conversation.id,
                    DateTime.now().toUtc().add(const Duration(days: 1)),
                    limit: 100,
                  );
                  logger.info(
                    'conversation=${_controller.conversation.id} count=$count recentIds=${recent.map((m) => m.id).join(',')}',
                  );
                } catch (e) {
                  final logger = const Logger('ChatPage.debug');
                  logger.error('error fetching debug info', e);
                }
              },
            ),
        ],
      ),
      body: Column(
        children: <Widget>[
          _buildConnectionBanner(),
          _buildJoinRequestBanners(),
          Expanded(child: _buildMessageList()),
          SafeArea(
            top: false,
            bottom: true,
            minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            child: _buildComposer(),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectionBanner() {
    return AnimatedBuilder(
      animation: _p2pController,
      builder: (context, _) {
        final role = _p2pController.role;
        if (role == null) {
          return const SizedBox.shrink();
        }

        late final IconData icon;
        late final String title;
        late final String details;

        if (role == P2pSessionRole.host) {
          icon = Icons.wifi_tethering;
          title = 'Hosting conversation';
          final state = _p2pController.hostState;
          if (state != null && state.isActive) {
            details =
                'SSID: ${state.ssid ?? 'pending'} · Password: ${state.preSharedKey ?? 'pending'}';
          } else {
            details = 'Hotspot starting…';
          }
        } else {
          icon = Icons.link;
          title = 'Joined conversation';
          final state = _p2pController.clientState;
          if (state != null && state.isActive) {
            details =
                'Connected to ${state.hostSsid ?? 'host'} · Gateway ${state.hostGatewayIpAddress ?? 'pending'}';
          } else {
            details = 'Waiting for connection…';
          }
        }

        final conversationTitle =
            _p2pController.activeConversationTitle ??
            _controller.conversation.title;
        final subtitle = '$details\nSharing: $conversationTitle';

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Card(
            child: ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
            ),
          ),
        );
      },
    );
  }

  /// Non-blocking banners shown to the **host** for each pending join
  /// request.  Each card shows the requester's profile image, display name,
  /// full name, class/group name, and role, with Confirm (green) and
  /// Deny (red) buttons.
  Widget _buildJoinRequestBanners() {
    return AnimatedBuilder(
      animation: _p2pController,
      builder: (context, _) {
        // Only the host sees join requests.
        if (_p2pController.role != P2pSessionRole.host) {
          return const SizedBox.shrink();
        }

        final requests = _p2pController.pendingJoinRequests;
        if (requests.isEmpty) {
          return const SizedBox.shrink();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final request in requests)
              _JoinRequestBanner(
                request: request,
                onApprove: () => _p2pController.approveJoinRequest(request),
                onDeny: () => _p2pController.denyJoinRequest(request),
              ),
          ],
        );
      },
    );
  }

  Widget _buildMessageList() {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.messages.isEmpty) {
          return const Center(
            child: Text('Start a conversation by sending a message.'),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          controller: _messageScrollController,
          itemCount: _controller.messages.length,
          itemBuilder: (context, index) {
            final message = _controller.messages[index];
            final scheme = Theme.of(context).colorScheme;
            final backgroundColor = message.isLocal
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest;
            final textColor = message.isLocal
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant;

            return Padding(
              key: ValueKey(message.id),
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                crossAxisAlignment: message.isLocal
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: message.isLocal
                        ? MainAxisAlignment.end
                        : MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (!message.isLocal) ...[
                        ProfileAvatar(
                          identity: message.senderIdentity,
                          size: 32,
                        ),
                        const SizedBox(width: 8),
                      ],
                      Flexible(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: backgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Text(
                                message.displaySender,
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: _scaledAlpha(textColor, 0.8),
                                    ),
                              ),
                              const SizedBox(height: 4),
                              // Message text
                              if (message.content.isNotEmpty) ...[
                                Text(
                                  message.content,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: textColor),
                                ),
                                const SizedBox(height: 4),
                              ],

                              // Attachments (images / files)
                              if (message.attachments.isNotEmpty)
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: message.attachments.map((a) {
                                    return _buildAttachmentWidget(
                                      context,
                                      a,
                                      message,
                                      textColor,
                                    );
                                  }).toList(),
                                ),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  message.sentAtFormatted,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: _scaledAlpha(textColor, 0.7),
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (message.isLocal) ...[
                        const SizedBox(width: 8),
                        ProfileAvatar(
                          identity: message.senderIdentity,
                          size: 32,
                        ),
                      ],
                    ],
                  ),
                  // Read receipt indicators — only shown on the most recent
                  // message each reader has seen (Messenger-style).
                  if (_controller.latestReadReceipts.containsKey(message.id))
                    Padding(
                      padding: EdgeInsets.only(
                        left: message.isLocal ? 0 : 40.0,
                        right: message.isLocal ? 40.0 : 0,
                      ),
                      child: ReadReceiptIndicator(
                        receipts: _controller.latestReadReceipts[message.id]!,
                        localUserId: _controller.localPeerId,
                        alignment: message.isLocal
                            ? MainAxisAlignment.end
                            : MainAxisAlignment.start,
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildComposer() {
    return Row(
      children: <Widget>[
        Expanded(
          child: TextField(
            controller: _controller.messageFieldController,
            focusNode: _composerFocusNode,
            decoration: const InputDecoration(hintText: 'Type a message'),
            onSubmitted: (_) => unawaited(_handleSend()),
          ),
        ),
        const SizedBox(width: 12),
        // File picker button (general files)
        IconButton(
          icon: const Icon(Icons.add),
          tooltip: 'Attach file',
          onPressed: () => unawaited(_handlePickFile()),
        ),
        // Image / video picker button
        IconButton(
          icon: const Icon(Icons.image),
          tooltip: 'Attach image or video',
          onPressed: () => unawaited(_handlePickMedia()),
        ),
        IconButton(
          icon: const Icon(Icons.send),
          onPressed: () => unawaited(_handleSend()),
        ),
      ],
    );
  }

  Future<void> _handlePickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: false);
      if (result == null) return;
      final path = result.files.single.path;
      if (path == null) return;

      // Copy picked file to a permanent location so the temp/cache path
      // can't be overwritten by subsequent picks (common on Android).
      final file = await _copyToStableAttachmentPath(File(path));

      final info = await _p2pController.sendAttachment(file);
      if (info == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unable to share file')));
        return;
      }

      // Create optimistic local message with attachment so UI updates immediately.
      final ext = p.extension(file.path).toLowerCase();
      final mime =
          (info.metadata['mimeType'] as String?) ?? _mimeTypeForExtension(ext);

      final attachment = ChatAttachment(
        id: info.id,
        filename: info.name,
        mimeType: mime,
        sizeBytes: info.size != 0 ? info.size : await file.length(),
        uri: file.path,
      );

      await _controller.sendLocalMessageWithAttachments(
        '',
        attachments: [attachment],
        attachmentsAreExternal: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('File pick failed: $e')));
    }
  }

  Future<void> _handlePickMedia() async {
    final picker = ImagePicker();
    final choice = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Image'),
              onTap: () => Navigator.of(context).pop('image'),
            ),
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('Video'),
              onTap: () => Navigator.of(context).pop('video'),
            ),
          ],
        ),
      ),
    );

    if (choice == null) return;

    try {
      XFile? picked;
      if (choice == 'image') {
        picked = await picker.pickImage(source: ImageSource.gallery);
      } else if (choice == 'video') {
        picked = await picker.pickVideo(source: ImageSource.gallery);
      }
      if (picked == null) return;

      // Copy picked file to a permanent location so the temp/cache path
      // can't be overwritten by subsequent picks (common on Android).
      final file = await _copyToStableAttachmentPath(File(picked.path));

      final info = await _p2pController.sendAttachment(file);
      if (info == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Unable to share media')));
        return;
      }

      // Create optimistic local message with attachment so UI updates immediately.
      final ext = p.extension(file.path).toLowerCase();
      final mime =
          (info.metadata['mimeType'] as String?) ?? _mimeTypeForExtension(ext);

      final attachment = ChatAttachment(
        id: info.id,
        filename: info.name,
        mimeType: mime,
        sizeBytes: info.size != 0 ? info.size : await file.length(),
        uri: file.path,
      );

      await _controller.sendLocalMessageWithAttachments(
        '',
        attachments: [attachment],
        attachmentsAreExternal: true,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Media pick failed: $e')));
    }
  }

  Future<void> _handleSend() async {
    final raw = _controller.messageFieldController.text;
    final message = await _controller.sendLocalMessage(raw);
    if (message == null) {
      return;
    }

    final payload = ChatMessagePayload.fromChatMessage(
      message,
      conversationTitle: _controller.conversation.title,
      senderIdentity:
          widget.testPeerIdentity ?? AppDependencies.instance.peerIdentity,
    );
    await _p2pController.sendChatMessage(payload);
  }

  void _handleMessagesChanged() {
    final count = _controller.messages.length;
    if (count != _lastMessageCount) {
      _lastMessageCount = count;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
      // Mark new messages as seen whenever the list updates (debounced to
      // avoid spamming receipts during rapid message arrival).
      _debouncedMarkSeen();
    }
  }

  void _handleComposerFocusChange() {
    if (_composerFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    }
  }

  void _scrollToBottom() {
    if (!_messageScrollController.hasClients) {
      return;
    }
    final position = _messageScrollController.position;
    position.animateTo(
      position.maxScrollExtent,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  Color _scaledAlpha(Color color, double factor) {
    final scaled = (color.a * factor).clamp(0.0, 1.0);
    return color.withAlpha((scaled * 255).round());
  }

  Future<void> _showLatencyDiagnostics() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => LatencyDiagnosticsSheet(controller: _p2pController),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ATTACHMENT RENDERING
  // ─────────────────────────────────────────────────────────────────────────

  /// Returns the appropriate icon for a file based on its mime type.
  IconData _iconForMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.videocam;
    if (mimeType.startsWith('audio/')) return Icons.audiotrack;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf;
    return Icons.insert_drive_file;
  }

  Widget _buildAttachmentWidget(
    BuildContext context,
    ChatAttachment a,
    ChatMessageViewModel message,
    Color textColor,
  ) {
    final uri = a.uri.trim();
    final isImage = a.mimeType.startsWith('image/');
    final isVideo = a.mimeType.startsWith('video/');
    final failureCount = _controller.downloadFailures[a.id] ?? 0;
    final isDownloading = failureCount < 3 && uri.isEmpty;
    final isDownloaded = uri.isNotEmpty && File(uri).existsSync();

    // ── Downloaded image — show inline with tap-to-preview ──
    if (isImage && isDownloaded) {
      return Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: GestureDetector(
          onTap: () => FullscreenImageViewer.open(
            context,
            file: File(uri),
            heroTag: 'attachment_${a.id}',
            title: a.filename,
          ),
          onLongPress: () => _showFileActionSheet(context, a, message),
          child: Hero(
            tag: 'attachment_${a.id}',
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200, maxHeight: 200),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(uri), fit: BoxFit.cover),
              ),
            ),
          ),
        ),
      );
    }

    // ── Downloaded video — show inline player with thumbnail + play ──
    if (isVideo && isDownloaded) {
      return Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: GestureDetector(
          onLongPress: () => _showFileActionSheet(context, a, message),
          child: InlineVideoPlayer(
            key: ValueKey(a.id),
            filePath: uri,
            filename: a.filename,
          ),
        ),
      );
    }

    // ── Downloaded non-media file — show file row with long-press ──
    if (isDownloaded) {
      return Padding(
        padding: const EdgeInsets.only(top: 6.0),
        child: GestureDetector(
          onLongPress: () => _showFileActionSheet(context, a, message),
          child: Row(
            children: [
              Icon(_iconForMimeType(a.mimeType)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  a.filename,
                  style: TextStyle(color: textColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.check_circle, size: 18, color: Colors.green),
            ],
          ),
        ),
      );
    }

    // ── File still downloading or failed ──
    return Padding(
      padding: const EdgeInsets.only(top: 6.0),
      child: GestureDetector(
        onLongPress: () => _showFileActionSheet(context, a, message),
        child: Row(
          children: [
            Icon(
              isDownloading ? Icons.downloading : _iconForMimeType(a.mimeType),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isDownloading ? '${a.filename} (downloading...)' : a.filename,
                style: TextStyle(color: textColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (failureCount >= 3)
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Retry download',
                onPressed: () async {
                  await _controller.requestAttachmentDownload(message.id, a);
                },
              )
            else if (isDownloading)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  /// Shows a bottom sheet with file actions (retry download, save location info).
  void _showFileActionSheet(
    BuildContext context,
    ChatAttachment attachment,
    ChatMessageViewModel message,
  ) {
    final isDownloaded =
        attachment.uri.isNotEmpty && File(attachment.uri).existsSync();
    final failureCount = _controller.downloadFailures[attachment.id] ?? 0;

    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  attachment.filename,
                  style: Theme.of(sheetContext).textTheme.titleMedium,
                  maxLines: 1,
                ),
              ),
            ),
            if (attachment.sizeBytes > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0),
                child: Text(
                  _formatFileSize(attachment.sizeBytes),
                  style: Theme.of(sheetContext).textTheme.bodySmall,
                ),
              ),
            if (isDownloaded) ...[
              ListTile(
                leading: const Icon(Icons.download),
                title: const Text('Save to Downloads'),
                onTap: () async {
                  Navigator.pop(sheetContext);
                  await _saveToDownloads(context, attachment);
                },
              ),
            ] else ...[
              ListTile(
                leading: const Icon(Icons.download),
                title: Text(failureCount > 0 ? 'Retry download' : 'Download'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  unawaited(
                    _controller.requestAttachmentDownload(
                      message.id,
                      attachment,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _saveToDownloads(
    BuildContext context,
    ChatAttachment attachment,
  ) async {
    try {
      const downloadsDir = '/storage/emulated/0/Download';
      final dir = Directory(downloadsDir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }

      final destPath = '$downloadsDir/${attachment.filename}';
      final destFile = File(destPath);

      // If a file with the same name already exists, add a suffix.
      var finalPath = destPath;
      if (destFile.existsSync()) {
        final baseName = p.basenameWithoutExtension(attachment.filename);
        final ext = p.extension(attachment.filename);
        var counter = 1;
        while (File(finalPath).existsSync()) {
          finalPath = '$downloadsDir/${baseName}_($counter)$ext';
          counter++;
        }
      }

      await File(attachment.uri).copy(finalPath);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to Downloads/${p.basename(finalPath)}'),
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to save: $e')));
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// Copies a picked file to a permanent attachments directory with a
  /// timestamp-keyed filename so that the original temp/cache path can be
  /// reused by subsequent picks without overwriting this file.
  Future<File> _copyToStableAttachmentPath(File source) async {
    final dir = await getApplicationDocumentsDirectory();
    final outDir = Directory('${dir.path}/attachments');
    if (!outDir.existsSync()) outDir.createSync(recursive: true);

    final ext = p.extension(source.path);
    final stableName = '${DateTime.now().microsecondsSinceEpoch}$ext';
    final stablePath = '${outDir.path}/$stableName';
    return source.copy(stablePath);
  }

  /// Maps a file extension (including leading dot) to a mime type.
  static String _mimeTypeForExtension(String ext) {
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.jpg':
      case '.jpeg':
        return 'image/jpeg';
      case '.gif':
        return 'image/gif';
      case '.webp':
        return 'image/webp';
      case '.heic':
        return 'image/heic';
      case '.mp4':
        return 'video/mp4';
      case '.mov':
        return 'video/quicktime';
      case '.avi':
        return 'video/x-msvideo';
      case '.mkv':
        return 'video/x-matroska';
      case '.pdf':
        return 'application/pdf';
      default:
        return 'application/octet-stream';
    }
  }
}

/// A non-blocking banner card shown at the top of the chat page when a
/// peer requests to join a private conversation that requires host approval.
///
/// Displays the requester's profile image, display name, full name (if
/// available), class/group name (if available), and role.  Provides green
/// Confirm and red Deny action buttons.
class _JoinRequestBanner extends StatelessWidget {
  const _JoinRequestBanner({
    required this.request,
    required this.onApprove,
    required this.onDeny,
  });

  final JoinRequest request;
  final VoidCallback onApprove;
  final VoidCallback onDeny;

  @override
  Widget build(BuildContext context) {
    final identity = request.toPeerIdentity();
    final theme = Theme.of(context);

    // Build subtitle parts: full name, group/class name, role.
    final subtitleParts = <String>[];
    if (request.fullName != null && request.fullName!.isNotEmpty) {
      subtitleParts.add(request.fullName!);
    }
    if (request.groupName != null && request.groupName!.isNotEmpty) {
      subtitleParts.add(request.groupName!);
    }
    if (request.role != null && request.role!.isNotEmpty) {
      subtitleParts.add(
        UserRole.values
            .firstWhere(
              (e) => e.name == request.role,
              orElse: () => UserRole.other,
            )
            .displayName,
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        color: theme.colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ProfileAvatar(identity: identity, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${request.displayName} wants to join',
                      style: theme.textTheme.titleSmall,
                    ),
                    if (subtitleParts.isNotEmpty)
                      Text(
                        subtitleParts.join(' · '),
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                icon: const Icon(Icons.close, size: 20),
                tooltip: 'Deny',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
                onPressed: onDeny,
              ),
              const SizedBox(width: 4),
              IconButton.filled(
                icon: const Icon(Icons.check, size: 20),
                tooltip: 'Confirm',
                style: IconButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
                onPressed: onApprove,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
