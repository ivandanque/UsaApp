import 'package:flutter/material.dart';

import '../../../../app/di/app_dependencies.dart';
import '../../data/datasources/drift_conversation_data_source.dart';
import '../../domain/entities/conversation.dart';
import 'conversation_history_page.dart';

/// Chats library — lists saved conversations and allows create/rename/delete.
class ChatsLibraryPage extends StatefulWidget {
  const ChatsLibraryPage({super.key});

  static const String routeName = '/chats';

  @override
  State<ChatsLibraryPage> createState() => _ChatsLibraryPageState();
}

class _ChatsLibraryPageState extends State<ChatsLibraryPage> {
  late final DriftConversationDataSource _store;
  late final Stream<List<Conversation>> _conversationsStream;
  bool _isRenaming = false;

  @override
  void initState() {
    super.initState();
    _store = AppDependencies.instance.conversationStore;
    _conversationsStream = _store.watchAll();
  }

  String _relativeTime(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) return 'Updated just now';
    if (difference.inHours < 1)
      return 'Updated ${difference.inMinutes} min ago';
    if (difference.inDays < 1) return 'Updated ${difference.inHours} h ago';
    return 'Updated ${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
  }

  Future<String?> _promptForName({
    required String title,
    String? initialValue,
  }) {
    return showDialog<String>(
      context: context,
      builder: (context) => _ConversationNameDialog(
        title: title,
        confirmLabel: 'Save',
        initialValue: initialValue ?? '',
      ),
    );
  }

  Future<void> _handleCreateConversation() async {
    final name = await _promptForName(title: 'Create new chat');
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    await _store.createConversation(trimmed);
  }

  Future<void> _deleteConversation(Conversation conversation) async {
    await _store.deleteConversation(conversation.id);
  }

  Future<void> _renameConversation(Conversation conversation) async {
    if (_isRenaming) return;
    final newName = await _promptForName(
      title: 'Rename chat',
      initialValue: conversation.title,
    );
    final trimmed = newName?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == conversation.title) return;
    setState(() => _isRenaming = true);
    try {
      await _store.renameConversation(id: conversation.id, newTitle: trimmed);
    } finally {
      if (mounted) setState(() => _isRenaming = false);
    }
  }

  void _openConversation(Conversation conversation) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConversationHistoryPage(conversation: conversation),
      ),
    );
  }

  Future<void> _handleConversationAction(
    _ConversationMenuAction action,
    Conversation conversation,
  ) async {
    switch (action) {
      case _ConversationMenuAction.rename:
        await _renameConversation(conversation);
        break;
      case _ConversationMenuAction.delete:
        await _deleteConversation(conversation);
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Saved Chats')),
      body: SafeArea(
        top: false,
        child: StreamBuilder<List<Conversation>>(
          stream: _conversationsStream,
          initialData: const <Conversation>[],
          builder: (context, snapshot) {
            final conversations = snapshot.data ?? const <Conversation>[];
            if (conversations.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'You have not saved any chats yet. Start a conversation, and it will appear here for easy access.',
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: conversations.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final conversation = conversations[index];
                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.chat_bubble_outline),
                    title: Text(conversation.title),
                    subtitle: Text(_relativeTime(conversation.updatedAt)),
                    onTap: () => _openConversation(conversation),
                    trailing: PopupMenuButton<_ConversationMenuAction>(
                      onSelected: (action) =>
                          _handleConversationAction(action, conversation),
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: _ConversationMenuAction.rename,
                          child: Text('Rename'),
                        ),
                        PopupMenuItem(
                          value: _ConversationMenuAction.delete,
                          child: Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _handleCreateConversation,
        tooltip: 'Create chat',
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _ConversationNameDialog extends StatefulWidget {
  const _ConversationNameDialog({
    required this.title,
    required this.confirmLabel,
    this.initialValue = '',
  });

  final String title;
  final String confirmLabel;
  final String initialValue;

  @override
  State<_ConversationNameDialog> createState() =>
      _ConversationNameDialogState();
}

class _ConversationNameDialogState extends State<_ConversationNameDialog> {
  late final TextEditingController _controller;
  late String _currentText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
    _currentText = widget.initialValue.trim();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    if (trimmed.isEmpty) return;
    Navigator.of(context).pop(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        autofocus: true,
        textInputAction: TextInputAction.done,
        onChanged: (value) => setState(() => _currentText = value.trim()),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _currentText.isEmpty ? null : _submit,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

enum _ConversationMenuAction { rename, delete }
