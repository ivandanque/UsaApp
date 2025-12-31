import 'package:flutter/material.dart';

import '../../features/chat/domain/entities/conversation.dart';
import '../../features/chat/presentation/pages/chat_page.dart';
import '../../features/chat/presentation/pages/chats_history_page.dart';
import '../../features/chat/presentation/pages/conversation_mode_page.dart';
import '../../features/home/presentation/pages/home_page.dart';
import '../../features/onboarding/presentation/pages/onboarding_page.dart';
import '../../features/settings/presentation/pages/profile_page.dart';
import '../../features/settings/presentation/pages/settings_page.dart';

class AppRouter {
  const AppRouter._();

  static Map<String, WidgetBuilder> get routes => <String, WidgetBuilder>{
    HomePage.routeName: (_) => const HomePage(),
    OnboardingPage.routeName: (_) => const OnboardingPage(),
    ConversationModePage.routeName: (_) => const ConversationModePage(),
    ChatsHistoryPage.routeName: (_) => const ChatsHistoryPage(),
    SettingsPage.routeName: (_) => const SettingsPage(),
    ProfilePage.routeName: (_) => const ProfilePage(),
  };

  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case OnboardingPage.routeName:
        return MaterialPageRoute<void>(
          builder: (_) => const OnboardingPage(),
          settings: settings,
        );
      case HomePage.routeName:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
      case ConversationModePage.routeName:
        return MaterialPageRoute<void>(
          builder: (_) => const ConversationModePage(),
          settings: settings,
        );
      case ChatPage.routeName:
        final args = settings.arguments;
        if (args is! Conversation) {
          return MaterialPageRoute<void>(
            builder: (_) => const ConversationModePage(),
            settings: settings,
          );
        }
        return MaterialPageRoute<void>(
          builder: (_) => ChatPage(conversation: args),
          settings: settings,
        );
      case ChatsHistoryPage.routeName:
        return MaterialPageRoute<void>(
          builder: (_) => const ChatsHistoryPage(),
          settings: settings,
        );
      case SettingsPage.routeName:
        return MaterialPageRoute<void>(
          builder: (_) => const SettingsPage(),
          settings: settings,
        );
      case ProfilePage.routeName:
        return MaterialPageRoute<void>(
          builder: (_) => const ProfilePage(),
          settings: settings,
        );
      default:
        return MaterialPageRoute<void>(
          builder: (_) => const HomePage(),
          settings: settings,
        );
    }
  }
}
