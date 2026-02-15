import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/features/p2p/presentation/controllers/p2p_session_controller.dart';
import 'package:usaapp/src/core/models/room_summary.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart' as p2p_pkg;
import 'package:usaapp/src/features/p2p/data/services/p2p_service.dart';
import 'package:usaapp/src/core/services/notification_service.dart';

class FakeNotificationService implements NotificationService {
  final List<List<RoomSummary>> roomsCalls = [];
  final List<Map<String, String>> connectionCalls = [];
  final List<void> disconnectionCalls = [];
  final List<String> peerJoinedCalls = [];
  final List<String> peerLeftCalls = [];
  final List<String> peerRejoinedCalls = [];

  @override
  void setNavigatorKey(globalKey) => null;

  @override
  Future<void> initialize({bool requestPermissions = true}) async {}

  @override
  Future<void> notifyConnected(String roomTitle, String hostName) async {
    connectionCalls.add({'room': roomTitle, 'host': hostName});
  }

  @override
  Future<void> notifyDisconnected() async {
    disconnectionCalls.add(null);
  }

  @override
  Future<void> notifyRoomsFound(List<RoomSummary> rooms) async {
    roomsCalls.add(List<RoomSummary>.from(rooms));
  }

  @override
  Future<void> requestPermissionIfNeeded() async {}

  @override
  Future<void> showScanningNotification() async {}

  @override
  Future<void> cancelScanningNotification() async {}

  @override
  Future<void> notifyPeerJoined(
    String displayName, {
    String? profileImageBase64,
  }) async {
    peerJoinedCalls.add(displayName);
  }

  @override
  Future<void> notifyPeerLeft(
    String displayName, {
    String? profileImageBase64,
  }) async {
    peerLeftCalls.add(displayName);
  }

  @override
  Future<void> notifyPeerRejoined(
    String displayName, {
    String? profileImageBase64,
  }) async {
    peerRejoinedCalls.add(displayName);
  }

  @override
  bool Function() vibrationEnabled = () => true;
}

class FakeClient implements p2p_pkg.FlutterP2pClient {
  final StreamController<List<p2p_pkg.BleDiscoveredDevice>> _controller =
      StreamController<List<p2p_pkg.BleDiscoveredDevice>>();

  // Expose a way to emit discovered devices in tests.
  void emitDevices(List<p2p_pkg.BleDiscoveredDevice> devices) {
    _controller.add(devices);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<StreamSubscription<List<p2p_pkg.BleDiscoveredDevice>>> startScan(
    void Function(List<p2p_pkg.BleDiscoveredDevice>)? onDevices, {
    void Function(Object)? onError,
    void Function()? onDone,
    bool? cancelOnError,
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final subscription = _controller.stream.listen(
      (devices) => onDevices?.call(devices),
      onDone: onDone,
      onError: onError,
      cancelOnError: cancelOnError,
    );
    return subscription;
  }

  @override
  Future<void> stopScan() async {
    await _controller.close();
  }

  @override
  Future<void> connectWithDevice(
    p2p_pkg.BleDiscoveredDevice device, {
    Duration? timeout,
  }) async {}

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> broadcastText(String text, {String? excludeClientId}) async {}

  @override
  Stream<p2p_pkg.HotspotClientState> streamHotspotState() {
    return const Stream<p2p_pkg.HotspotClientState>.empty();
  }

  @override
  Stream<String> streamReceivedTexts() async* {
    // no events
  }

  @override
  Stream<List<p2p_pkg.P2pClientInfo>> streamClientList() async* {
    // Emit empty list once; no further events during tests.
    yield <p2p_pkg.P2pClientInfo>[];
  }

  // Unused in tests; provide noSuchMethod
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeP2pService extends P2pService {
  final FakeClient client = FakeClient();

  @override
  Future<p2p_pkg.FlutterP2pClient> ensureClientInitialized() async => client;

  @override
  Future<void> checkAndRequestPermissions({
    P2pSessionRole role = P2pSessionRole.host,
    bool requestIfMissing = true,
  }) async {}

  @override
  Future<void> checkAndEnableServices({
    P2pSessionRole role = P2pSessionRole.host,
  }) async {}

  @override
  Future<void> disposeRole(P2pSessionRole role) async {}
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppDependencies.instance.initForTestsMinimal();
  });

  test('scan discovery enqueues and flushes to NotificationService', () async {
    final fakeNotif = FakeNotificationService();
    final fakeP2p = FakeP2pService();
    final controller = P2pSessionController(
      p2pService: fakeP2p,
      notificationService: fakeNotif,
      backgroundScanningEnabled: () => true,
      scanCadenceSeconds: () => 1,
    );

    // Set role to client so startDiscovery is allowed
    await controller.selectRole(P2pSessionRole.client);

    // Start discovery
    await controller.startDiscovery();

    // Emit a discovered device
    final device = p2p_pkg.BleDiscoveredDevice(
      deviceName: 'room1',
      deviceAddress: 'addr1',
    );
    fakeP2p.client.emitDevices([device]);

    // Stop discovery which triggers flush in onFinally
    await controller.stopDiscovery();

    // Allow microtasks to run
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(fakeNotif.roomsCalls.isNotEmpty, isTrue);
    expect(fakeNotif.roomsCalls.first.first.roomTitle, equals('room1'));

    controller.dispose();
  });

  test('connect and disconnect send notifications', () async {
    final fakeNotif = FakeNotificationService();
    final fakeP2p = FakeP2pService();
    final controller = P2pSessionController(
      p2pService: fakeP2p,
      notificationService: fakeNotif,
      backgroundScanningEnabled: () => false,
      scanCadenceSeconds: () => 5,
    );

    // Set client role
    await controller.selectRole(P2pSessionRole.client);

    final device = p2p_pkg.BleDiscoveredDevice(
      deviceName: 'room2',
      deviceAddress: 'addr2',
    );

    // Connect
    await controller.connectToDiscoveredHost(device);

    // Allow microtasks
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fakeNotif.connectionCalls, isNotEmpty);
    expect(fakeNotif.connectionCalls.first['room'], contains('room2'));

    // Disconnect
    await controller.disconnectFromHost();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(fakeNotif.disconnectionCalls.length, greaterThanOrEqualTo(1));

    controller.dispose();
  });
}
