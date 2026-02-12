import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/features/settings/presentation/controllers/settings_controller.dart';
import 'package:usaapp/src/features/p2p/data/services/p2p_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FakeP2pForSettings extends P2pService {
  bool _perms = true;
  bool _services = true;

  @override
  Future<void> checkAndRequestPermissions({P2pSessionRole role = P2pSessionRole.host, bool requestIfMissing = true}) async {
    // no-op
  }

  @override
  Future<bool> areAllPermissionsGranted({P2pSessionRole role = P2pSessionRole.host, bool requestIfMissing = true}) async {
    return _perms;
  }

  @override
  Future<void> checkAndEnableServices({P2pSessionRole role = P2pSessionRole.host}) async {
    // no-op
  }

  @override
  Future<bool> areAllServicesEnabled({P2pSessionRole role = P2pSessionRole.host}) async {
    return _services;
  }
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    await AppDependencies.instance.initForTestsMinimal();
  });

  test('setupPermissions and setupServices update controller state', () async {
    final fake = FakeP2pForSettings();
    final ctrl = SettingsController(p2pService: fake);

    await ctrl.setupPermissions();
    expect(ctrl.allPermissionsGranted, isTrue);
    expect(ctrl.isCheckingPermissions, isFalse);

    await ctrl.setupServices();
    expect(ctrl.allServicesEnabled, isTrue);
    expect(ctrl.isCheckingServices, isFalse);
  });

  test('refreshStatus and persistence setters update values', () async {
    final ctrl = SettingsController(p2pService: FakeP2pForSettings());

    await AppDependencies.instance.setBackgroundScanningEnabled(true);
    await AppDependencies.instance.setScanCadenceSeconds(10);

    await ctrl.refreshStatus();
    expect(ctrl.backgroundScanningEnabled, isTrue);
    expect(ctrl.scanCadenceSeconds, equals(10));

    await ctrl.setBackgroundScanningEnabled(false);
    expect(AppDependencies.instance.backgroundScanningEnabled, isFalse);
    expect(ctrl.backgroundScanningEnabled, isFalse);

    await ctrl.setScanCadenceSeconds(0); // should coerce to 1
    expect(AppDependencies.instance.scanCadenceSeconds, equals(1));
    expect(ctrl.scanCadenceSeconds, equals(1));
  });
}
