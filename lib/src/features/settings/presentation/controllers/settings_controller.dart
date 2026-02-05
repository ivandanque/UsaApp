import 'package:flutter/foundation.dart';

import '../../../../app/di/app_dependencies.dart';
import '../../../../core/utils/logger.dart';
import '../../../p2p/data/services/p2p_service.dart';

/// Controller for managing P2P settings and setup.
class SettingsController extends ChangeNotifier {
  SettingsController({P2pService? p2pService})
      : _logger = const Logger('SettingsController'),
        _p2pService = p2pService ?? AppDependencies.instance.p2pService;

  final Logger _logger;
  final P2pService _p2pService;

  bool _isCheckingPermissions = false;
  bool _isCheckingServices = false;
  bool _allPermissionsGranted = false;
  bool _allServicesEnabled = false;
  bool _isSavingDisplayName = false;
  String _displayName = '';
  String _deviceCode = '';
  bool _backgroundScanningEnabled = false;
  int _scanCadenceSeconds = 5;

  bool get isCheckingPermissions => _isCheckingPermissions;
  bool get isCheckingServices => _isCheckingServices;
  bool get allPermissionsGranted => _allPermissionsGranted;
  bool get allServicesEnabled => _allServicesEnabled;
  bool get isP2pReady => _allPermissionsGranted && _allServicesEnabled;
  bool get isSavingDisplayName => _isSavingDisplayName;
  String get displayName => _displayName;
  String get deviceCode => _deviceCode;
  bool get backgroundScanningEnabled => _backgroundScanningEnabled;
  int get scanCadenceSeconds => _scanCadenceSeconds;

  /// Check and request all necessary permissions.
  Future<void> setupPermissions() async {
    _isCheckingPermissions = true;
    notifyListeners();

    try {
      await _p2pService.checkAndRequestPermissions();
      _allPermissionsGranted = await _p2pService.areAllPermissionsGranted();
      _logger.info('Permissions setup completed: $_allPermissionsGranted');
    } catch (e) {
      _logger.error('Error setting up permissions: $e');
      _allPermissionsGranted = false;
    } finally {
      _isCheckingPermissions = false;
      notifyListeners();
    }
  }

  /// Check and enable all necessary services.
  Future<void> setupServices() async {
    _isCheckingServices = true;
    notifyListeners();

    try {
      await _p2pService.checkAndEnableServices();
      _allServicesEnabled = await _p2pService.areAllServicesEnabled();
      _logger.info('Services setup completed: $_allServicesEnabled');
    } catch (e) {
      _logger.error('Error setting up services: $e');
      _allServicesEnabled = false;
    } finally {
      _isCheckingServices = false;
      notifyListeners();
    }
  }

  /// Refresh the status of permissions and services.
  Future<void> refreshStatus() async {
    try {
      _allPermissionsGranted = await _p2pService.areAllPermissionsGranted(
        requestIfMissing: false,
      );
      _allServicesEnabled = await _p2pService.areAllServicesEnabled();
      // Load persisted scanning preferences
      _backgroundScanningEnabled = AppDependencies.instance.backgroundScanningEnabled;
      _scanCadenceSeconds = AppDependencies.instance.scanCadenceSeconds;
      final identity = AppDependencies.instance.peerIdentity;
      _displayName = identity.displayName;
      _deviceCode = identity.id;
      notifyListeners();
    } catch (e) {
      _logger.error('Error refreshing status: $e');
    }
  }

  Future<void> setBackgroundScanningEnabled(bool enabled) async {
    try {
      await AppDependencies.instance.setBackgroundScanningEnabled(enabled);
      _backgroundScanningEnabled = enabled;
      notifyListeners();
    } catch (e) {
      _logger.error('Error setting background scanning: $e');
    }
  }

  Future<void> setScanCadenceSeconds(int seconds) async {
    final effective = seconds > 0 ? seconds : 1;
    try {
      await AppDependencies.instance.setScanCadenceSeconds(effective);
      _scanCadenceSeconds = effective;
      notifyListeners();
    } catch (e) {
      _logger.error('Error setting scan cadence: $e');
    }
  }

  Future<String> updateDisplayName(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty && _displayName.trim().isEmpty) {
      return _displayName;
    }

    _isSavingDisplayName = true;
    notifyListeners();

    try {
      await AppDependencies.instance.updatePeerDisplayName(trimmed);
      final updatedIdentity = AppDependencies.instance.peerIdentity;
      _displayName = updatedIdentity.displayName;
      _deviceCode = updatedIdentity.id;
    } catch (e) {
      _logger.error('Error updating display name: $e');
    } finally {
      _isSavingDisplayName = false;
      notifyListeners();
    }

    return _displayName;
  }
}
