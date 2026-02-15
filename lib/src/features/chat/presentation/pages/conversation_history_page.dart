import 'dart:async';

import 'package:flutter/material.dart';
import 'dart:io';
import '../../../../core/utils/logger.dart';
import '../../../../core/widgets/profile_avatar.dart';
import '../widgets/fullscreen_image_viewer.dart';
import '../widgets/inline_video_player.dart';

import '../../../../app/di/app_dependencies.dart';
import '../../data/datasources/drift_conversation_data_source.dart';
import '../../domain/entities/conversation.dart';
import '../controllers/chat_controller.dart';

class ConversationHistoryPage extends StatefulWidget {
  const ConversationHistoryPage({super.key, required this.conversation});

  final Conversation conversation;

  @override
  State<ConversationHistoryPage> createState() =>
      _ConversationHistoryPageState();
}

class _ConversationHistoryPageState extends State<ConversationHistoryPage> {
  final Logger _logger = const Logger('ConversationHistoryPage');
  Widget _buildAttachments(ChatMessageViewModel message) {
    if (message.attachments.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: message.attachments.map((a) {
        final filename = a.filename.isNotEmpty
            ? a.filename
            : (a.uri.isNotEmpty ? a.uri : '');
        if (a.mimeType.startsWith('image/') && a.uri.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: GestureDetector(
              onTap: () => FullscreenImageViewer.open(
                context,
                file: File(a.uri),
                heroTag: 'history_attachment_${a.id}',
                title: a.filename,
              ),
              child: Hero(
                tag: 'history_attachment_${a.id}',
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(a.uri),
                    width: 160,
                    height: 120,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stack) =>
                        const Icon(Icons.broken_image),
                  ),
                ),
              ),
            ),
          );
        } else if (a.mimeType.startsWith('video/') && a.uri.isNotEmpty) {
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: InlineVideoPlayer(
              filePath: a.uri,
              filename: filename,
              maxWidth: 200,
              maxHeight: 140,
            ),
          );
        } else {
          final icon = a.mimeType.startsWith('video/')
              ? Icons.videocam
              : a.mimeType.startsWith('audio/')
                  ? Icons.audiotrack
                  : a.mimeType == 'application/pdf'
                      ? Icons.picture_as_pdf
                      : Icons.insert_drive_file;
          return Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 6),
                Flexible(child: Text(filename)),
              ],
            ),
          );
        }
      }).toList(),
    );
  }

  late final ChatController _chatController;
  late final DriftConversationDataSource _conversationStore;
  late final StreamSubscription<List<Conversation>> _conversationSubscription;
  final ScrollController _scrollController = ScrollController();

  Conversation? _currentConversation;

  @override
  void initState() {
    super.initState();
    _conversationStore = AppDependencies.instance.conversationStore;
    _currentConversation = widget.conversation;
    _chatController = AppDependencies.instance.createChatController(
      conversation: widget.conversation,
    );
    _logger.info(
      '[ConversationHistoryPage] created controller=${_chatController.hashCode} convo=${widget.conversation.id}',
    );

    _conversationSubscription = _conversationStore.watchAll().listen((items) {
      final match = items
          .where((item) => item.id == widget.conversation.id)
          .toList();
      if (match.isEmpty) {
        if (mounted) {
          Navigator.of(context).maybePop();
        }
        return;
      }
      final updated = match.first;
      if (_currentConversation?.title != updated.title) {
        setState(() => _currentConversation = updated);
      }
      _chatController.conversation = updated;
    });

    // Register listener before starting the controller to ensure the
    // initial DB emission delivered by the controller triggers a rebuild
    // rather than being missed due to a race.
    _chatController.addListener(_handleMessagesChanged);

    unawaited(_chatController.start());
  }

  @override
  void dispose() {
    _chatController.removeListener(_handleMessagesChanged);
    _conversationSubscription.cancel();
    _chatController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conversationTitle = _currentConversation?.title ?? 'Conversation';

    return Scaffold(
      appBar: AppBar(title: Text(conversationTitle)),
      body: SafeArea(
        top: false,
        child: AnimatedBuilder(
          animation: _chatController,
          builder: (context, _) {
            final messages = _chatController.messages;
            final loaded = _chatController.hasLoadedInitial;
            _logger.info(
              '[ConversationHistoryPage] controller=${_chatController.hashCode} messages=${messages.length} ids=${messages.map((m) => m.id).toList()} convo=${_currentConversation?.id}',
            );

            if (!loaded) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text('Loading messages...'),
                    ],
                  ),
                ),
              );
            }

            if (messages.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'No messages have been recorded for this chat yet.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final message = messages[index];
                final alignment = message.isLocal
                    ? Alignment.centerRight
                    : Alignment.centerLeft;
                final theme = Theme.of(context);
                final scheme = theme.colorScheme;
                final backgroundColor = message.isLocal
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHighest;
                final textColor = message.isLocal
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant;

                return Align(
                  alignment: alignment,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Profile avatar
                      Padding(
                        padding: const EdgeInsets.only(right: 8.0, top: 4.0),
                        child: ProfileAvatar(
                          identity: message.senderIdentity,
                          size: 28,
                        ),
                      ),
                      Flexible(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
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
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: _scaledAlpha(textColor, 0.8),
                                ),
                              ),
                              const SizedBox(height: 4),
                              if (message.content.isNotEmpty)
                                Text(
                                  message.content,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    color: textColor,
                                  ),
                                ),
                              // Attachments (images/files)
                              _buildAttachments(message),
                              const SizedBox(height: 4),
                              Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  message.sentAtFormatted,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: _scaledAlpha(textColor, 0.7),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  void _handleMessagesChanged() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  Color _scaledAlpha(Color color, double factor) {
    final scaled = (color.a * factor).clamp(0.0, 1.0);
    return color.withAlpha((scaled * 255).round());
  }
}
