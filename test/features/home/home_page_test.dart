// removed unused import
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/features/home/presentation/pages/home_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppDependencies.instance.initForTestsMinimal();
  });

  group('HomePage', () {
    group('app bar', () {
      testWidgets('displays app title', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.text('UsaApp'), findsOneWidget);
      });
    });

    group('welcome section', () {
      testWidgets('displays welcome message', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.text('Welcome to UsaApp'), findsOneWidget);
      });
    });

    group('navigation tiles', () {
      testWidgets('displays View Chats tile', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.text('View Chats'), findsOneWidget);
      });

      testWidgets('displays Conversations tile', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.text('Conversations'), findsOneWidget);
      });

      testWidgets('displays Profile tile', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.text('Profile'), findsOneWidget);
      });

      testWidgets('displays Settings tile', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
      });

      testWidgets('displays profile tile subtitle', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(
          find.text('Edit your name, profile image, group, and role.'),
          findsOneWidget,
        );
      });
    });

    group('navigation icons', () {
      testWidgets('displays history icon for View Chats', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.history_toggle_off), findsOneWidget);
      });

      testWidgets('displays message icon for Conversations', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.message_outlined), findsOneWidget);
      });

      testWidgets('displays person icon for Profile', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.person_outlined), findsOneWidget);
      });

      testWidgets('displays settings icon for Settings', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: HomePage()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
      });
    });
  });
}
