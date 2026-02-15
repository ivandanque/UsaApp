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

  testWidgets('toggling background scanning persists and updates cadence',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsPage()));
    await tester.pumpAndSettle();

    // Initially background scanning should be false
    final initial = AppDependencies.instance.backgroundScanningEnabled;
    expect(initial, isFalse);

    // Toggle the switch on
    final switchFinder = find.widgetWithText(SwitchListTile, 'Background scanning');
    expect(switchFinder, findsOneWidget);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(AppDependencies.instance.backgroundScanningEnabled, isTrue);

    // Cadence card should now be visible
    final addButton = find.widgetWithIcon(IconButton, Icons.add);
    expect(addButton, findsOneWidget);

    final beforeCadence = AppDependencies.instance.scanCadenceSeconds;

    // Tap add to increment cadence
    await tester.tap(addButton);
    await tester.pumpAndSettle();

    expect(AppDependencies.instance.scanCadenceSeconds, equals(beforeCadence + 1));

    // Tap remove to decrement cadence
    final removeButton = find.widgetWithIcon(IconButton, Icons.remove);
    expect(removeButton, findsOneWidget);
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(AppDependencies.instance.scanCadenceSeconds, equals(beforeCadence));
  });
}
