// removed unused import
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/core/models/peer_identity.dart';
import 'package:usaapp/src/features/onboarding/presentation/pages/onboarding_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppDependencies.instance.initForTestsMinimal();
  });

  group('OnboardingPage', () {
    group('welcome page', () {
      testWidgets('displays app title', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        expect(find.text('Welcome to UsaApp'), findsOneWidget);
      });

      testWidgets('displays welcome icon', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.chat_bubble_outline), findsOneWidget);
      });

      testWidgets('displays Next button', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        expect(find.text('Next'), findsOneWidget);
      });
    });

    group('navigation', () {
      testWidgets('can navigate to permissions page', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        expect(find.text('Permissions Needed'), findsOneWidget);
      });

      testWidgets('can navigate back from permissions page', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Back'));
        await tester.pumpAndSettle();

        expect(find.text('Welcome to UsaApp'), findsOneWidget);
      });
    });

    group('permissions page', () {
      testWidgets('displays location permission info', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        expect(find.text('Location & Nearby Devices'), findsOneWidget);
      });

      testWidgets('displays bluetooth permission info', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        expect(find.text('Bluetooth Access'), findsOneWidget);
      });

      testWidgets('displays storage permission info', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        expect(find.text('Media & Storage'), findsOneWidget);
      });
    });

    group('setup page', () {
      testWidgets('displays setup title', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        // Navigate to setup page
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        expect(find.text('Setup P2P Connection'), findsOneWidget);
      });

      testWidgets('displays Start Setup button', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        // Navigate to setup page
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Next'));
        await tester.pumpAndSettle();

        expect(find.text('Start Setup'), findsOneWidget);
      });
    });

    group('page indicators', () {
      testWidgets('displays three page indicators', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: OnboardingPage()));
        await tester.pumpAndSettle();

        // Page indicators are rendered as Containers with circle decoration
        final indicators = find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.decoration is BoxDecoration &&
              (widget.decoration as BoxDecoration).shape == BoxShape.circle,
        );

        expect(indicators, findsNWidgets(3));
      });
    });
  });

  group('Profile Setup Form', () {
    group('UserRole enum', () {
      test('student role has correct display name', () {
        expect(UserRole.student.displayName, equals('Student'));
      });

      test('teacher role has correct display name', () {
        expect(UserRole.teacher.displayName, equals('Teacher'));
      });

      test('other role has correct display name', () {
        expect(UserRole.other.displayName, equals('Other'));
      });
    });
  });
}
