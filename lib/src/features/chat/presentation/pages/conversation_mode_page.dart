import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

import '../../../../app/di/app_dependencies.dart';
import '../../../p2p/data/services/p2p_service.dart';
import '../../../p2p/presentation/controllers/p2p_session_controller.dart';
import '../../data/datasources/drift_conversation_data_source.dart';
import '../../domain/entities/conversation.dart';
import 'chat_page.dart';
import '../../../../app/routes/app_route_names.dart';

class ConversationModePage extends StatefulWidget {
  const ConversationModePage({super.key, P2pSessionController? controller})
    : _controller = controller;

  static const routeName = AppRouteNames.conversationMode;

  final P2pSessionController? _controller;

  @override
  State<ConversationModePage> createState() => _ConversationModePageState();
}

class _ConversationModePageState extends State<ConversationModePage> {
  late final P2pSessionController _controller;
  late final bool _ownsController;
  late DriftConversationDataSource _conversationStore;
  List<Conversation> _conversations = <Conversation>[];
  StreamSubscription<List<Conversation>>? _conversationsSub;
  Conversation? _selectedConversation;
  bool _hasAutoOpenedForSession = false;

  @override
  @override
  void initState() {
    super.initState();
    _controller =
        widget._controller ??
        AppDependencies.instance.createP2pSessionController();
    _ownsController = widget._controller == null;
    _conversationStore = AppDependencies.instance.conversationStore;
    // Always refresh the subscription on page open
    _conversationsSub?.cancel();
    _conversationsSub = _conversationStore.watchAll().listen((list) {
      setState(() => _conversations = list);
    });
  }

  @override
  void dispose() {
    if (_ownsController) {
      _controller.dispose();
    }
    _conversationsSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Conversations')),
      body: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          _scheduleAutoOpenIfNeeded();

          return Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'How would you like to connect?',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    ChoiceChip(
                      label: const Text('Host on this device'),
                      selected: _controller.role == P2pSessionRole.host,
                      onSelected: _controller.isBusy
                          ? null
                          : (selected) {
                              if (selected) {
                                _controller.selectRole(P2pSessionRole.host);
                              }
                            },
                    ),
                    ChoiceChip(
                      label: const Text('Join an existing host'),
                      selected: _controller.role == P2pSessionRole.client,
                      onSelected: _controller.isBusy
                          ? null
                          : (selected) {
                              if (selected) {
                                _controller.selectRole(P2pSessionRole.client);
                              }
                            },
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (_controller.isBusy) const LinearProgressIndicator(),
                if (_controller.errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _controller.errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Expanded(child: _buildModeContent(context)),
                const SizedBox(height: 16),
                SafeArea(
                  top: false,
                  left: false,
                  right: false,
                  minimum: const EdgeInsets.only(bottom: 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Open conversation'),
                      onPressed: _controller.hasActiveSession
                          ? _openChat
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildModeContent(BuildContext context) {
    final role = _controller.role;
    if (role == P2pSessionRole.host) {
      return _HostModeSection(controller: _controller);
    }
    if (role == P2pSessionRole.client) {
      return _ClientModeSection(controller: _controller);
    }

    return Center(
      child: Text(
        'Select whether you want to host a conversation or join one nearby.',
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
    );
  }

  Future<void> _openChat({bool preferActiveConversation = false}) async {
    if (!_controller.hasActiveSession) {
      return;
    }

    await _controller.waitForActiveConversationSync();

    Conversation? conversation;
    bool isPrivate = false;
    String? passwordHash;

    if (preferActiveConversation) {
      final activeId = _controller.activeConversationId;
      if (activeId != null) {
        conversation = _findConversationById(activeId);
        if (conversation == null) {
          final ensured = await _conversationStore.ensureConversationExists(
            id: activeId,
            title: _controller.activeConversationTitle ?? 'Conversation',
          );
          conversation = ensured;
        }
      }
    }

    if (conversation == null && _selectedConversation != null) {
      conversation = _selectedConversation;
    }

    if (conversation == null) {
      final result = await _showConversationPicker();
      if (result == null) {
        _refreshSelectedConversation();
        return;
      }
      conversation = result.conversation;
      isPrivate = result.isPrivate;
      passwordHash = result.passwordHash;
    }

    final conversationToOpen = conversation;
    setState(() => _selectedConversation = conversationToOpen);
    
    // If joining a private conversation as a client, prompt for password
    if (isPrivate && _controller.role == P2pSessionRole.client) {
      final password = await _promptForPassword();
      if (password == null) {
        _refreshSelectedConversation();
        return;
      }
      // Verify password
      final verifiedHash = _hashPassword(password);
      if (passwordHash != null && verifiedHash != passwordHash) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Incorrect password. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
        _refreshSelectedConversation();
        return;
      }
    }
    
    _controller.setActiveConversation(
      conversationToOpen,
      isPrivate: isPrivate,
      passwordHash: passwordHash,
    );

    if (!mounted) {
      return;
    }

    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatPage(
          conversation: conversationToOpen,
          p2pController: _controller,
        ),
      ),
    );
  }

  Future<String?> _promptForPassword() async {
    return showDialog<String>(
      context: context,
      builder: (context) => const _PasswordPromptDialog(),
    );
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void _scheduleAutoOpenIfNeeded() {
    final hasSession = _controller.hasActiveSession;

    if (!hasSession) {
      _hasAutoOpenedForSession = false;
      return;
    }

    final shouldAutoOpen =
        _controller.role == P2pSessionRole.client &&
        !_controller.isBusy &&
        !_hasAutoOpenedForSession;

    if (!shouldAutoOpen) {
      return;
    }

    final activeConversationId = _controller.activeConversationId;
    if (activeConversationId == null) {
      return;
    }

    _hasAutoOpenedForSession = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      _openChat(preferActiveConversation: true);
    });
  }

  Conversation? _findConversationById(String id) {
    for (final conversation in _conversations) {
      if (conversation.id == id) {
        return conversation;
      }
    }
    return null;
  }

  void _refreshSelectedConversation() {
    final current = _selectedConversation;
    if (current == null) {
      return;
    }
    final matches = _conversations
        .where((candidate) => candidate.id == current.id)
        .toList();
    if (matches.isEmpty) {
      setState(() => _selectedConversation = null);
      return;
    }

    final updated = matches.first;
    if (updated.title != current.title) {
      setState(() => _selectedConversation = updated);
    }
  }

  Future<({Conversation conversation, bool isPrivate, String? passwordHash})?> _showConversationPicker() async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ConversationPickerSheet(
        store: _conversationStore,
        selectedConversationId: _selectedConversation?.id,
      ),
    );

    if (result == null) return null;
    
    // Result can be either a Conversation or a record with privacy details
    if (result is Conversation) {
      return (conversation: result, isPrivate: false, passwordHash: null);
    } else {
      return result as ({Conversation conversation, bool isPrivate, String? passwordHash});
    }
  }
}

class _ConversationPickerSheet extends StatefulWidget {
  const _ConversationPickerSheet({
    required this.store,
    this.selectedConversationId,
  });

  final DriftConversationDataSource store;
  final String? selectedConversationId;

  @override
  State<_ConversationPickerSheet> createState() =>
      _ConversationPickerSheetState();
}

class _ConversationPickerSheetState extends State<_ConversationPickerSheet> {
  bool _isCreating = false;
  late final Stream<List<Conversation>> _conversationsStream;

  @override
  void initState() {
    super.initState();
    _conversationsStream = widget.store.watchAll();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final media = MediaQuery.of(context);
        final bottomPadding = media.viewInsets.bottom + 24;

        return AnimatedPadding(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 24,
            bottom: bottomPadding,
          ),
          child: SizedBox(
            height: constraints.maxHeight,
            child: Column(
              mainAxisSize: MainAxisSize.max,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FilledButton.icon(
                  icon: _isCreating
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add_comment_outlined),
                  label: Text(_isCreating ? 'Creating…' : 'Create new chat'),
                  onPressed: _isCreating ? null : _handleCreatePressed,
                ),
                const SizedBox(height: 24),
                Text(
                  'Choose an existing conversation',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: StreamBuilder<List<Conversation>>(
                    stream: _conversationsStream,
                    builder: (context, snapshot) {
                      final conversations =
                          snapshot.data ?? const <Conversation>[];
                      if (conversations.isEmpty) {
                        return const Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              'No conversations yet. Create a new one!',
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: conversations.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final conversation = conversations[index];
                          final isSelected =
                              widget.selectedConversationId == conversation.id;
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              isSelected
                                  ? Icons.radio_button_checked
                                  : Icons.radio_button_off,
                            ),
                            title: Text(conversation.title),
                            subtitle: Text(
                              'Updated ${_relativeTime(conversation.updatedAt)}',
                            ),
                            onTap: () =>
                                Navigator.of(context).pop(conversation),
                            trailing: PopupMenuButton<_ConversationAction>(
                              onSelected: (action) =>
                                  _onConversationAction(action, conversation),
                              itemBuilder: (context) => const [
                                PopupMenuItem<_ConversationAction>(
                                  value: _ConversationAction.rename,
                                  child: Text('Rename'),
                                ),
                                PopupMenuItem<_ConversationAction>(
                                  value: _ConversationAction.delete,
                                  child: Text('Delete'),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _handleCreatePressed() async {
    final details = await _promptForConversationDetails();
    if (details == null) return;
    final trimmedName = details.name.trim();
    if (trimmedName.isEmpty) return;

    setState(() => _isCreating = true);
    try {
      final conversation = await widget.store.createConversation(trimmedName);
      String? passwordHash;
      if (details.isPrivate && details.password != null) {
        passwordHash = _hashPassword(details.password!);
      }
      if (!mounted) {
        return;
      }
      // Return conversation with privacy metadata
      Navigator.of(context).pop((
        conversation: conversation,
        isPrivate: details.isPrivate,
        passwordHash: passwordHash,
      ));
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  String _hashPassword(String password) {
    final bytes = utf8.encode(password);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  Future<({String name, bool isPrivate, String? password})?> _promptForConversationDetails() async {
    return showDialog<({String name, bool isPrivate, String? password})>(
      context: context,
      builder: (context) => const _ConversationDetailsDialog(
        title: 'Create new chat',
        confirmLabel: 'Create',
      ),
    );
  }

  String _relativeTime(DateTime timestamp) {
    final difference = DateTime.now().difference(timestamp);
    if (difference.inMinutes < 1) {
      return 'just now';
    }
    if (difference.inHours < 1) {
      return '${difference.inMinutes} min ago';
    }
    if (difference.inDays < 1) {
      return '${difference.inHours} h ago';
    }
    return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
  }

  Future<void> _onConversationAction(
    _ConversationAction action,
    Conversation conversation,
  ) async {
    switch (action) {
      case _ConversationAction.rename:
        await _renameConversation(conversation);
        break;
      case _ConversationAction.delete:
        await _confirmDeleteConversation(conversation);
        break;
    }
  }

  Future<void> _renameConversation(Conversation conversation) async {
    final result = await showDialog<String>(
      context: context,
      builder: (context) => _ConversationNameDialog(
        title: 'Rename chat',
        confirmLabel: 'Save',
        initialValue: conversation.title,
      ),
    );

    final trimmed = result?.trim() ?? '';
    if (trimmed.isEmpty || trimmed == conversation.title) {
      return;
    }

    await widget.store.renameConversation(
      id: conversation.id,
      newTitle: trimmed,
    );

    if (!mounted) {
      return;
    }

    if (widget.selectedConversationId == conversation.id) {
      final navigator = Navigator.of(context);
      final updated = await widget.store.getConversationById(conversation.id);
      navigator.pop(updated);
    }
  }

  Future<void> _confirmDeleteConversation(Conversation conversation) async {
    final shouldDelete =
        await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Delete chat?'),
              content: Text(
                'This will remove "${conversation.title}" and its messages from this device. This action cannot be undone.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Delete'),
                ),
              ],
            );
          },
        ) ??
        false;

    if (!shouldDelete) {
      return;
    }

    await widget.store.deleteConversation(conversation.id);

    if (!mounted) {
      return;
    }

    if (widget.selectedConversationId == conversation.id) {
      Navigator.of(context).pop(null);
    }
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
    if (trimmed.isEmpty) {
      return;
    }
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
        decoration: const InputDecoration(labelText: 'Conversation name'),
        onChanged: (value) {
          setState(() => _currentText = value.trim());
        },
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

enum _ConversationAction { rename, delete }

class _ConversationDetailsDialog extends StatefulWidget {
  const _ConversationDetailsDialog({
    required this.title,
    required this.confirmLabel,
  });

  final String title;
  final String confirmLabel;

  @override
  State<_ConversationDetailsDialog> createState() =>
      _ConversationDetailsDialogState();
}

class _ConversationDetailsDialogState extends State<_ConversationDetailsDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _passwordController;
  bool _isPrivate = false;
  String _currentName = '';
  String _currentPassword = '';
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _passwordController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmedName = _nameController.text.trim();
    if (trimmedName.isEmpty) return;
    if (_isPrivate && _currentPassword.trim().isEmpty) return;

    Navigator.of(context).pop((
      name: trimmedName,
      isPrivate: _isPrivate,
      password: _isPrivate ? _currentPassword : null,
    ));
  }

  bool get _canSubmit {
    if (_currentName.trim().isEmpty) return false;
    if (_isPrivate && _currentPassword.trim().isEmpty) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Conversation name'),
              textInputAction: TextInputAction.next,
              onChanged: (value) => setState(() => _currentName = value),
              onSubmitted: (_) => _isPrivate ? null : _submit(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Private chat',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
                Switch(
                  value: _isPrivate,
                  onChanged: (value) => setState(() => _isPrivate = value),
                ),
              ],
            ),
            if (_isPrivate) ...[
              const SizedBox(height: 8),
              Text(
                'Set a password to protect this conversation. '
                'Guests will need to enter it to join.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(
                  labelText: 'Password',
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility : Icons.visibility_off,
                    ),
                    onPressed: () {
                      setState(() => _obscurePassword = !_obscurePassword);
                    },
                  ),
                ),
                obscureText: _obscurePassword,
                textInputAction: TextInputAction.done,
                onChanged: (value) => setState(() => _currentPassword = value),
                onSubmitted: (_) => _canSubmit ? _submit() : null,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _canSubmit ? _submit : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

class _HostModeSection extends StatelessWidget {
  const _HostModeSection({required this.controller});

  final P2pSessionController controller;

  @override
  Widget build(BuildContext context) {
    final hostState = controller.hostState;
    final isActive = controller.isHostingActive;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isActive
                      ? 'Your hotspot is live. Share the details below so peers can join.'
                      : 'Create a hotspot so nearby peers can discover and join you.',
                  style: theme.textTheme.bodyLarge,
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.wifi_tethering),
                  label: Text(
                    isActive ? 'Refresh hotspot' : 'Create group & advertise',
                  ),
                  onPressed: controller.isBusy
                      ? null
                      : () => controller.createGroupAndAdvertise(),
                ),
                const SizedBox(height: 16),
                if (isActive && hostState != null) ...[
                  _HostDetails(state: hostState),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Stop hosting'),
                    onPressed: controller.isBusy
                        ? null
                        : () => controller.removeGroup(),
                  ),
                ] else ...[
                  Text(
                    'We will check your permissions and enable Wi‑Fi, location, and Bluetooth as needed.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ClientModeSection extends StatelessWidget {
  const _ClientModeSection({required this.controller});

  final P2pSessionController controller;

  @override
  Widget build(BuildContext context) {
    final devices = controller.discoveredDevices;
    final clientState = controller.clientState;
    final isConnected = controller.isClientConnected;
    final isScanning = controller.isScanning;
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isConnected
              ? 'Connected to ${clientState?.hostSsid ?? 'host'}. You are ready to chat.'
              : 'Scan for nearby hosts to join their conversation.',
          style: theme.textTheme.bodyLarge,
        ),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          icon: Icon(isScanning ? Icons.pause : Icons.search),
          label: Text(isScanning ? 'Stop discovery' : 'Discover nearby hosts'),
          onPressed: controller.isBusy
              ? null
              : () {
                  if (isScanning) {
                    controller.stopDiscovery();
                  } else {
                    controller.startDiscovery();
                  }
                },
        ),
        const SizedBox(height: 16),
        if (devices.isEmpty && !isScanning && !isConnected)
          Text(
            'No advertised host found yet. Start discovery to look for peers.',
            style: theme.textTheme.bodyMedium,
          )
        else
          Expanded(
            child: _DiscoveredDevicesList(
              devices: devices,
              onConnect: controller.isBusy
                  ? null
                  : (device) {
                      controller.connectToDiscoveredHost(device);
                    },
            ),
          ),
        if (isConnected && clientState != null) ...[
          const SizedBox(height: 12),
          _ClientDetails(state: clientState),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: const Icon(Icons.link_off),
            label: const Text('Disconnect'),
            onPressed: controller.isBusy
                ? null
                : () => controller.disconnectFromHost(),
          ),
        ],
      ],
    );
  }
}

class _DiscoveredDevicesList extends StatelessWidget {
  const _DiscoveredDevicesList({
    required this.devices,
    required this.onConnect,
  });

  final List<BleDiscoveredDevice> devices;
  final ValueChanged<BleDiscoveredDevice>? onConnect;

  @override
  Widget build(BuildContext context) {
    if (devices.isEmpty) {
      return Center(
        child: Text(
          'Looking for hosts…',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }

    return ListView.separated(
      itemCount: devices.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final device = devices[index];
        return ListTile(
          title: Text(device.deviceName),
          subtitle: Text(device.deviceAddress),
          trailing: IconButton(
            icon: const Icon(Icons.link),
            tooltip: 'Connect',
            onPressed: onConnect == null ? null : () => onConnect!(device),
          ),
        );
      },
    );
  }
}

class _HostDetails extends StatelessWidget {
  const _HostDetails({required this.state});

  final HotspotHostState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'SSID: ${state.ssid ?? 'Unavailable'}',
          style: theme.textTheme.bodySmall,
        ),
        SelectableText(
          'Password: ${state.preSharedKey ?? 'Unavailable'}',
          style: theme.textTheme.bodySmall,
        ),
        SelectableText(
          'Host IP: ${state.hostIpAddress ?? 'Pending'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _ClientDetails extends StatelessWidget {
  const _ClientDetails({required this.state});

  final HotspotClientState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          'Host SSID: ${state.hostSsid ?? 'Unknown'}',
          style: theme.textTheme.bodySmall,
        ),
        SelectableText(
          'Gateway IP: ${state.hostGatewayIpAddress ?? 'Unknown'}',
          style: theme.textTheme.bodySmall,
        ),
        SelectableText(
          'Device IP: ${state.hostIpAddress ?? 'Unknown'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _PasswordPromptDialog extends StatefulWidget {
  const _PasswordPromptDialog();

  @override
  State<_PasswordPromptDialog> createState() => _PasswordPromptDialogState();
}

class _PasswordPromptDialogState extends State<_PasswordPromptDialog> {
  late final TextEditingController _controller;
  bool _obscurePassword = true;
  String _currentPassword = '';

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final password = _controller.text.trim();
    if (password.isEmpty) return;
    Navigator.of(context).pop(password);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Private Conversation'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This conversation is password protected. Enter the password to join.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: 'Password',
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() => _obscurePassword = !_obscurePassword);
                },
              ),
            ),
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onChanged: (value) => setState(() => _currentPassword = value),
            onSubmitted: (_) => _currentPassword.isNotEmpty ? _submit() : null,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _currentPassword.isEmpty ? null : _submit,
          child: const Text('Join'),
        ),
      ],
    );
  }
}
