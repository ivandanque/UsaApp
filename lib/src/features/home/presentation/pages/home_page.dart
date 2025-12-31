import 'package:flutter/material.dart';

import '../../../chat/presentation/pages/conversation_mode_page.dart';
import '../../../chat/presentation/pages/chats_history_page.dart';
import '../../../settings/presentation/pages/profile_page.dart';
import '../../../settings/presentation/pages/settings_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  static const routeName = '/';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('UsaApp')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: <Widget>[
          Text('Welcome to UsaApp', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 12),
          Text(
            'Choose where you would like to start. You can review saved chats, tweak your settings, or jump right into conversations.',
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          _DestinationTile(
            icon: Icons.history_toggle_off,
            title: 'View Chats',
            subtitle: 'Browse saved conversations, rename them, or clear logs.',
            onTap: () =>
                Navigator.of(context).pushNamed(ChatsHistoryPage.routeName),
          ),
          _DestinationTile(
            icon: Icons.message_outlined,
            title: 'Conversations',
            subtitle: 'Continue chatting with your current peers.',
            onTap: () =>
                Navigator.of(context).pushNamed(ConversationModePage.routeName),
          ),
          _DestinationTile(
            icon: Icons.person_outlined,
            title: 'Profile',
            subtitle: 'Edit your name, profile image, group, and role.',
            onTap: () => Navigator.of(context).pushNamed(ProfilePage.routeName),
          ),
          _DestinationTile(
            icon: Icons.settings_outlined,
            title: 'Settings',
            subtitle: 'Adjust P2P permissions and services.',
            onTap: () =>
                Navigator.of(context).pushNamed(SettingsPage.routeName),
          ),
        ],
      ),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 8),
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }
}
