// removed unused import
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/core/models/peer_identity.dart';
import 'package:usaapp/src/features/settings/presentation/pages/profile_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppDependencies.instance.initForTestsMinimal();
  });

  group('ProfilePage', () {
    group('app bar', () {
      testWidgets('displays Edit Profile title', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Edit Profile'), findsOneWidget);
      });

      testWidgets('displays save button', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.check), findsOneWidget);
      });
    });

    group('profile avatar', () {
      testWidgets('displays profile avatar', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.byType(CircleAvatar), findsWidgets);
      });
    });

    group('form fields', () {
      testWidgets('displays Display Name field', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Display Name'), findsOneWidget);
      });

      testWidgets('displays Full Name field', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Full Name'), findsOneWidget);
      });

      testWidgets('displays Group/Class Name field', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Group/Class Name'), findsOneWidget);
      });

      testWidgets('displays Role dropdown', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Role'), findsOneWidget);
      });
    });

    group('profile image section', () {
      testWidgets('displays Profile Image heading', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Scroll down to find the profile image section
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();

        expect(find.text('Profile Image'), findsOneWidget);
      });

      testWidgets('displays Choose Image button', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Scroll down to find the button
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();

        expect(find.text('Choose Image'), findsOneWidget);
      });

      testWidgets('displays image picker icon', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Scroll down to find the icon
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.photo_library), findsOneWidget);
      });

      testWidgets('displays no image selected initially', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Scroll down to find the text
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();

        expect(find.text('No image selected'), findsOneWidget);
      });
    });

    group('profile preview', () {
      testWidgets('displays Profile Preview heading after scrolling', (
        tester,
      ) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Scroll down to find the profile preview section
        await tester.drag(find.byType(ListView), const Offset(0, -400));
        await tester.pumpAndSettle();

        expect(find.text('Profile Preview'), findsOneWidget);
      });
    });

    group('role dropdown', () {
      testWidgets('displays role options when tapped', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Find and tap the dropdown using the DropdownButtonFormField with UserRole type
        final dropdown = find.byType(DropdownButtonFormField<UserRole>);
        expect(dropdown, findsOneWidget);

        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        expect(find.text('Student'), findsWidgets);
        expect(find.text('Teacher'), findsWidgets);
        expect(find.text('Other'), findsWidgets);
      });
    });

    group('display name validation', () {
      testWidgets('shows error when display name is empty', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Find display name field and clear it
        final displayNameFields = find.byType(TextFormField);
        // First TextFormField is Display Name
        await tester.enterText(displayNameFields.first, '');

        // Tap save button
        await tester.tap(find.byIcon(Icons.check));
        await tester.pumpAndSettle();

        expect(find.text('Display name is required'), findsOneWidget);
      });
    });

    group('helper text', () {
      testWidgets('displays display name helper text', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Name shown in chats'), findsOneWidget);
      });

      testWidgets('displays full name helper text', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Your full name (optional)'), findsOneWidget);
      });

      testWidgets('displays group name helper text', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        expect(find.text('Your class or group (optional)'), findsOneWidget);
      });

      testWidgets('displays image size recommendation', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: ProfilePage()));
        await tester.pumpAndSettle();

        // Scroll down to find the text
        await tester.drag(find.byType(ListView), const Offset(0, -200));
        await tester.pumpAndSettle();

        expect(
          find.text('Recommended: Square image, max 500KB'),
          findsOneWidget,
        );
      });
    });
  });
}
