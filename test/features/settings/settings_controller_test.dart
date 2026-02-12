import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/features/p2p/data/services/p2p_service.dart';
import 'package:usaapp/src/features/settings/presentation/controllers/settings_controller.dart';

class FakeP2pService extends P2pService {
  bool permissionsRequested = false;
  bool servicesEnabled = false;

  @override
  Future<void> checkAndRequestPermissions({
    P2pSessionRole role = P2pSessionRole.host,
    bool requestIfMissing = true,
  }) async {
    permissionsRequested = true;
  }

  @override
  Future<void> checkAndEnableServices({
    P2pSessionRole role = P2pSessionRole.host,
  }) async {
    servicesEnabled = true;
  }

  @override
  Future<bool> areAllPermissionsGranted({
    P2pSessionRole role = P2pSessionRole.host,
    bool requestIfMissing = true,
  }) async {
    return true;
  }

  @override
  Future<bool> areAllServicesEnabled({
    P2pSessionRole role = P2pSessionRole.host,
  }) async {
    return true;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppDependencies.instance.initForTestsMinimal();
  });

  late FakeP2pService fakeService;
  late SettingsController controller;

  setUp(() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    fakeService = FakeP2pService();
    controller = SettingsController(p2pService: fakeService);
  });

  tearDown(() {
    controller.dispose();
  });

  test('refreshStatus loads prefs and identity', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('pref_background_scanning_enabled', true);
    await prefs.setInt('pref_scan_cadence_seconds', 9);

    await controller.refreshStatus();

    expect(controller.backgroundScanningEnabled, isTrue);
    expect(controller.scanCadenceSeconds, equals(9));
    expect(controller.displayName, isNotEmpty);
    expect(controller.deviceCode, isNotEmpty);
  });

  test('setBackgroundScanningEnabled persists value', () async {
    await controller.setBackgroundScanningEnabled(true);
    expect(controller.backgroundScanningEnabled, isTrue);
    expect(AppDependencies.instance.backgroundScanningEnabled, isTrue);
  });

  test('setScanCadenceSeconds persists positive value', () async {
    await controller.setScanCadenceSeconds(7);
    expect(controller.scanCadenceSeconds, equals(7));
    expect(AppDependencies.instance.scanCadenceSeconds, equals(7));
  });

  test('updateDisplayName stores new name', () async {
    final result = await controller.updateDisplayName('New Name');
    expect(result, equals('New Name'));
    expect(controller.displayName, equals('New Name'));
  });

  test('setupPermissions and services use injected service', () async {
    await controller.setupPermissions();
    await controller.setupServices();
    expect(fakeService.permissionsRequested, isTrue);
    expect(fakeService.servicesEnabled, isTrue);
    expect(controller.allPermissionsGranted, isTrue);
    expect(controller.allServicesEnabled, isTrue);
  });
}
