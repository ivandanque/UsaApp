// removed unused import
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/features/settings/presentation/pages/settings_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppDependencies.instance.initForTestsMinimal();
  });

  group('SettingsPage', () {
    group('app bar', () {
      testWidgets('displays Settings title', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.text('Settings'), findsOneWidget);
      });
    });

    group('P2P setup section', () {
      testWidgets('displays P2P Connection Setup heading', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.text('P2P Connection Setup'), findsOneWidget);
      });

      testWidgets('displays Permissions card', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.text('Permissions'), findsOneWidget);
      });

      testWidgets('displays Services card', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.text('Services'), findsOneWidget);
      });

      testWidgets('displays Setup button for Permissions', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.widgetWithText(ElevatedButton, 'Setup'), findsWidgets);
      });
    });

    group('device info section', () {
      testWidgets('displays Device ID label', (tester) async {
        await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
        await tester.pumpAndSettle();

        expect(find.text('Device ID'), findsOneWidget);
      });
    });
  });
}
