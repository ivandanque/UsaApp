import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:usaapp/src/app/di/app_dependencies.dart';
import 'package:usaapp/src/core/models/room_summary.dart';
import 'package:usaapp/src/core/services/notification_service.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart' as p2p_pkg;

import 'package:flutter/foundation.dart';
import 'package:flutter_p2p_connection/flutter_p2p_connection.dart';

import '../../../chat/domain/entities/chat_message_payload.dart';
import '../../../chat/domain/entities/conversation.dart';
import '../../../chat/data/datasources/drift_conversation_data_source.dart';
import '../../data/services/p2p_service.dart';
import '../../data/services/latency_probe_service.dart';

const String _conversationAnnouncementPrefix = '__usaapp_conversation__:';
const String _conversationRequestMessage = '__usaapp_request_conversation__';

class P2pSessionController extends ChangeNotifier {
  P2pSessionController({
    required P2pService p2pService,
    DriftConversationDataSource? conversationStore,
    LatencyProbeService? latencyProbeService,
    NotificationService? notificationService,
    bool Function()? backgroundScanningEnabled,
    int Function()? scanCadenceSeconds,
  }) : _p2pService = p2pService,
       _conversationStore = conversationStore,
       _latencyProbeService = latencyProbeService,
       _notificationService = notificationService ??
           AppDependencies.instance.notificationService,
       _backgroundScanningEnabled = backgroundScanningEnabled ??
           (() => AppDependencies.instance.backgroundScanningEnabled),
       _scanCadenceSeconds = scanCadenceSeconds ??
           (() => AppDependencies.instance.scanCadenceSeconds);

  final P2pService _p2pService;
  final DriftConversationDataSource? _conversationStore;
  final LatencyProbeService? _latencyProbeService;
  final NotificationService _notificationService;
  final bool Function() _backgroundScanningEnabled;
  final int Function() _scanCadenceSeconds;

  Timer? _roomsNotificationTimer;
  final List<RoomSummary> _pendingRoomSummaries = <RoomSummary>[];
  final Set<String> _pendingRoomKeys = <String>{};

  P2pSessionRole? _role;
  bool _isBusy = false;
  String? _statusMessage;
  String? _errorMessage;

  String? _activeConversationId;
  String? _activeConversationTitle;

  HotspotHostState? _hostState;
  HotspotClientState? _clientState;

  StreamSubscription<HotspotHostState>? _hostStateSubscription;
  StreamSubscription<HotspotClientState>? _clientStateSubscription;
  StreamSubscription<List<BleDiscoveredDevice>>? _scanSubscription;
  StreamSubscription<String>? _hostTextSubscription;
  StreamSubscription<String>? _clientTextSubscription;

  final List<BleDiscoveredDevice> _discoveredDevices = <BleDiscoveredDevice>[];
  bool _isScanning = false;
  final StreamController<ChatMessagePayload> _incomingMessagesController =
      StreamController<ChatMessagePayload>.broadcast();
  bool _pendingConversationAnnouncement = false;
  Future<void>? _pendingConversationSync;

  bool get isBusy => _isBusy;
  bool get isScanning => _isScanning;
  bool get isHostingActive => _hostState?.isActive ?? false;
  bool get isClientConnected => _clientState?.isActive ?? false;
  bool get hasActiveSession {
    if (_role == P2pSessionRole.host) {
      return isHostingActive;
    }
    if (_role == P2pSessionRole.client) {
      return isClientConnected;
    }
    return false;
  }

  String? get statusMessage => _statusMessage;
  String? get errorMessage => _errorMessage;
  P2pSessionRole? get role => _role;
  HotspotHostState? get hostState => _hostState;
  HotspotClientState? get clientState => _clientState;
  List<BleDiscoveredDevice> get discoveredDevices =>
      List<BleDiscoveredDevice>.unmodifiable(_discoveredDevices);
  Stream<ChatMessagePayload> get incomingMessages =>
      _incomingMessagesController.stream;
  String? get activeConversationId => _activeConversationId;
  String? get activeConversationTitle => _activeConversationTitle;

  Future<void> waitForActiveConversationSync() async {
    final pending = _pendingConversationSync;
    if (pending == null) {
      return;
    }

    try {
      await pending;
    } catch (_) {
      // Ignore storage sync errors here; they are surfaced elsewhere.
    }
  }

  void setActiveConversation(Conversation conversation) {
    _activeConversationId = conversation.id;
    _activeConversationTitle = conversation.title;
    _ensureConversationSynced(id: conversation.id, title: conversation.title);
    if (_role == P2pSessionRole.host) {
      _pendingConversationAnnouncement = true;
      if (isHostingActive) {
        unawaited(_announceActiveConversation());
      }
    }
    notifyListeners();
  }

  Future<void> selectRole(P2pSessionRole role) async {
    if (_role == role && _errorMessage == null) {
      return;
    }
    _role = role;
    _statusMessage = null;
    _errorMessage = null;
    notifyListeners();

    await _prepareRole(role);
  }

  Future<void> createGroupAndAdvertise() async {
    if (_role != P2pSessionRole.host) {
      _setError('Select "Host on this device" to create a group.');
      return;
    }

    await _guardedAction(() async {
      final host = await _p2pService.ensureHostInitialized();
      await _p2pService.checkAndRequestPermissions(role: P2pSessionRole.host);
      await _p2pService.checkAndEnableServices(role: P2pSessionRole.host);
      final state = await host.createGroup(advertise: true);
      _hostState = state;
      _statusMessage =
          'Hosting ${state.ssid ?? 'conversation'} (${state.hostIpAddress ?? 'pending IP'})';
      _errorMessage = null;
    });
  }

  Future<void> removeGroup() async {
    if (_role != P2pSessionRole.host) {
      return;
    }

    await _guardedAction(() async {
      final host = await _p2pService.ensureHostInitialized();
      await host.removeGroup();
      _statusMessage = 'Hosting stopped.';
    });
  }

  Future<void> startDiscovery() async {
    if (_role != P2pSessionRole.client) {
      _setError('Select "Join an existing host" to discover peers.');
      return;
    }
    if (_isScanning) {
      return;
    }

    await _guardedAction(() async {
      final client = await _p2pService.ensureClientInitialized();
      await _p2pService.checkAndRequestPermissions(role: P2pSessionRole.client);
      await _p2pService.checkAndEnableServices(role: P2pSessionRole.client);

      _discoveredDevices.clear();
      _isScanning = true;
      notifyListeners();

      try {
        _scanSubscription = await client.startScan(
          (devices) {
            _discoveredDevices
              ..clear()
              ..addAll(devices);
            _enqueueRoomsForNotification(devices);
            notifyListeners();
          },
          onDone: () {
            _isScanning = false;
            _statusMessage ??= 'Scan finished.';
            notifyListeners();
          },
          onError: (Object error) {
            _isScanning = false;
            _setError('Discovery error: $error');
          },
        );
      } catch (e) {
        _isScanning = false;
        rethrow;
      }

      _statusMessage = 'Scanning for nearby hosts...';
      _errorMessage = null;
    });
  }

  Future<void> stopDiscovery() async {
    if (_role != P2pSessionRole.client) {
      return;
    }

    await _guardedAction(
      () async {
        final client = await _p2pService.ensureClientInitialized();
        await client.stopScan();
      },
      onFinally: () async {
        await _scanSubscription?.cancel();
        _scanSubscription = null;
        _isScanning = false;
        notifyListeners();
        unawaited(_flushRoomNotifications());
        _cancelNotificationTimer();
      },
    );
  }

  Future<void> connectToDiscoveredHost(BleDiscoveredDevice device) async {
    if (_role != P2pSessionRole.client) {
      _setError('Switch to client mode before connecting.');
      return;
    }

    await _guardedAction(() async {
      final client = await _p2pService.ensureClientInitialized();
      if (_isScanning) {
        await client.stopScan();
        await _scanSubscription?.cancel();
        _scanSubscription = null;
        _isScanning = false;
        notifyListeners();
      }

      _statusMessage =
          'Connecting to ${device.deviceName.isNotEmpty ? device.deviceName : device.deviceAddress}...';
      notifyListeners();

      try {
        await client.connectWithDevice(
          device,
          timeout: const Duration(seconds: 45),
        );
      } on TimeoutException catch (e) {
        _statusMessage = null;
        final details =
            e.message ?? 'Timed out while waiting for host credentials.';
        _setError(
          'Connection timed out. Ensure the host is advertising and Bluetooth is enabled on both devices. ($details)',
        );
        return;
      }
      _statusMessage =
          'Connected to ${device.deviceName.isNotEmpty ? device.deviceName : device.deviceAddress}.';
      _errorMessage = null;
      final resolvedRoomTitle = device.deviceName.isNotEmpty
          ? device.deviceName
          : 'Nearby host';
      final resolvedHostName = device.deviceAddress.isNotEmpty
          ? device.deviceAddress
          : 'Unidentified host';
      unawaited(
        _notificationService.notifyConnected(
          resolvedRoomTitle,
          resolvedHostName,
        ),
      );
      unawaited(client.broadcastText(_conversationRequestMessage));
    });
  }

  Future<void> disconnectFromHost() async {
    if (_role != P2pSessionRole.client) {
      return;
    }

    await _guardedAction(() async {
      final client = await _p2pService.ensureClientInitialized();
      await client.disconnect();
      _statusMessage = 'Disconnected from host.';
      unawaited(_notificationService.notifyDisconnected());
    });
  }

  Future<void> sendGroupText(String message) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty || _role == null) {
      return;
    }

    try {
      if (_role == P2pSessionRole.host) {
        if (!isHostingActive) {
          _setError('Start hosting before broadcasting messages.');
          return;
        }
        final host = await _p2pService.ensureHostInitialized();
        await host.broadcastText(trimmed);
      } else {
        if (!isClientConnected) {
          _setError('Connect to a host before sending messages.');
          return;
        }
        final client = await _p2pService.ensureClientInitialized();
        await client.broadcastText(trimmed);
      }
    } catch (e) {
      _setError('Unable to send message over P2P: $e');
    }
  }

  Future<void> sendChatMessage(ChatMessagePayload payload) {
    _activeConversationId = payload.conversationId;
    _activeConversationTitle = payload.conversationTitle;
    notifyListeners();
    return sendGroupText(payload.encode());
  }

  void clearError() {
    if (_errorMessage != null) {
      _errorMessage = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _hostStateSubscription?.cancel();
    _clientStateSubscription?.cancel();
    _scanSubscription?.cancel();
    _hostTextSubscription?.cancel();
    _clientTextSubscription?.cancel();
    unawaited(_incomingMessagesController.close());

    final activeRole = _role;
    if (activeRole != null) {
      unawaited(_p2pService.disposeRole(activeRole));
    }

    _cancelNotificationTimer();
    unawaited(_flushRoomNotifications());

    super.dispose();
  }

  Future<void> _prepareRole(P2pSessionRole role) async {
    await _guardedAction(() async {
      if (role == P2pSessionRole.host) {
        _clientTextSubscription?.cancel();
        _clientTextSubscription = null;
      } else {
        _hostTextSubscription?.cancel();
        _hostTextSubscription = null;
      }

      if (role == P2pSessionRole.host) {
        final host = await _p2pService.ensureHostInitialized();
        _listenToHost(host);
      } else {
        final client = await _p2pService.ensureClientInitialized();
        _listenToClient(client);
      }

      await _p2pService.checkAndRequestPermissions(role: role);
      await _p2pService.checkAndEnableServices(role: role);

      _statusMessage = role == P2pSessionRole.host
          ? 'Ready to host a conversation.'
          : 'Ready to join a conversation.';
    });
  }

  Future<void> _guardedAction(
    Future<void> Function() action, {
    Future<void> Function()? onFinally,
  }) async {
    if (_isBusy) {
      return;
    }

    _isBusy = true;
    notifyListeners();

    try {
      await action();
    } catch (e) {
      _setError('$e');
    } finally {
      _isBusy = false;
      notifyListeners();
      if (onFinally != null) {
        await onFinally();
      }
    }
  }

  void _enqueueRoomsForNotification(List<BleDiscoveredDevice> devices) {
    if (!_backgroundScanningEnabled()) {
      return;
    }

    var added = false;
    for (final device in devices) {
      final key = '${device.deviceName}|${device.deviceAddress}';
      if (_pendingRoomKeys.add(key)) {
        _pendingRoomSummaries.add(
          RoomSummary(
            roomTitle: device.deviceName.isNotEmpty
                ? device.deviceName
                : 'Nearby room',
            hostName: device.deviceAddress.isNotEmpty
                ? device.deviceAddress
                : 'Unknown host',
          ),
        );
        added = true;
      }
    }

    if (added) {
      _ensureNotificationTimerRunning();
    }
  }

  void _ensureNotificationTimerRunning() {
    if (_roomsNotificationTimer != null || !_backgroundScanningEnabled()) {
      return;
    }

    _roomsNotificationTimer = Timer.periodic(
      _notificationInterval(),
      (_) => unawaited(_flushRoomNotifications()),
    );
  }

  Duration _notificationInterval() {
    final seconds = _scanCadenceSeconds();
    return Duration(seconds: seconds > 0 ? seconds : 5);
  }

  Future<void> _flushRoomNotifications() async {
    if (!_backgroundScanningEnabled()) {
      _pendingRoomSummaries.clear();
      _pendingRoomKeys.clear();
      _cancelNotificationTimer();
      return;
    }

    if (_pendingRoomSummaries.isEmpty) {
      return;
    }

    final batch = List<RoomSummary>.from(_pendingRoomSummaries);
    _pendingRoomSummaries.clear();
    _pendingRoomKeys.clear();

    try {
      await _notificationService.notifyRoomsFound(batch);
    } catch (e) {
      debugPrint('Room notification failed: $e');
    }
  }

  void _cancelNotificationTimer() {
    _roomsNotificationTimer?.cancel();
    _roomsNotificationTimer = null;
  }

  void _listenToHost(FlutterP2pHost host) {
    _hostStateSubscription?.cancel();
    _hostStateSubscription = host.streamHotspotState().listen((state) {
      _hostState = state;
      if (state.isActive && _pendingConversationAnnouncement) {
        unawaited(_announceActiveConversation());
      }
      notifyListeners();
    }, onError: (Object error) => _setError('Host state stream error: $error'));

    _hostTextSubscription?.cancel();
    _hostTextSubscription = host.streamReceivedTexts().listen(
      _handleIncomingText,
      onError: (Object error) {
        _setError('Host text stream error: $error');
      },
    );
  }

  void _listenToClient(FlutterP2pClient client) {
    _clientStateSubscription?.cancel();
    _clientStateSubscription = client.streamHotspotState().listen(
      (state) {
        _clientState = state;
        notifyListeners();
      },
      onError: (Object error) => _setError('Client state stream error: $error'),
    );

    _clientTextSubscription?.cancel();
    _clientTextSubscription = client.streamReceivedTexts().listen(
      _handleIncomingText,
      onError: (Object error) => _setError('Client text stream error: $error'),
    );
  }

  void _handleIncomingText(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return;
    }

    if (_latencyProbeService?.isLatencyPacket(trimmed) == true) {
      final service = _latencyProbeService!;
      unawaited(
        service
            .tryHandleIncomingPacket(
              message: trimmed,
              sendReply: (message) => sendGroupText(message),
            )
            .catchError((Object error, StackTrace stackTrace) {
              debugPrint('Latency packet handling failed: $error');
              return false;
            }),
      );
      return;
    }

    if (trimmed == _conversationRequestMessage) {
      if (_role == P2pSessionRole.host) {
        _pendingConversationAnnouncement = true;
        if (isHostingActive) {
          unawaited(_announceActiveConversation());
        }
      }
      return;
    }

    if (trimmed.startsWith(_conversationAnnouncementPrefix)) {
      final payloadRaw = trimmed.substring(
        _conversationAnnouncementPrefix.length,
      );
      try {
        final decoded = jsonDecode(payloadRaw);
        if (decoded is Map<String, dynamic>) {
          final conversationId = decoded['id'];
          final conversationTitle = decoded['title'];
          if (conversationId is String && conversationId.isNotEmpty) {
            final title =
                conversationTitle is String && conversationTitle.isNotEmpty
                ? conversationTitle
                : 'Conversation';
            _activeConversationId = conversationId;
            _activeConversationTitle = title;
            _ensureConversationSynced(id: conversationId, title: title);
            notifyListeners();
          }
        }
      } catch (_) {
        // Ignore malformed metadata packets.
      }
      return;
    }

    final payload =
        ChatMessagePayload.tryParse(trimmed) ??
        ChatMessagePayload.fallback(trimmed);
    _activeConversationId = payload.conversationId;
    _activeConversationTitle = payload.conversationTitle;
    _ensureConversationSynced(
      id: payload.conversationId,
      title: payload.conversationTitle,
    );
    notifyListeners();
    if (!_incomingMessagesController.isClosed) {
      _incomingMessagesController.add(payload);
    }
  }

  Future<void> _announceActiveConversation() async {
    final conversationId = _activeConversationId;
    final conversationTitle = _activeConversationTitle;
    if (conversationId == null || conversationTitle == null) {
      _pendingConversationAnnouncement = false;
      return;
    }

    final roleSnapshot = _role;
    if (roleSnapshot == null) {
      _pendingConversationAnnouncement = true;
      return;
    }

    _pendingConversationAnnouncement = false;
    final metadata = jsonEncode(<String, dynamic>{
      'id': conversationId,
      'title': conversationTitle,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
    final message = '$_conversationAnnouncementPrefix$metadata';

    try {
      if (roleSnapshot == P2pSessionRole.host) {
        final host = await _p2pService.ensureHostInitialized();
        await host.broadcastText(message);
      } else {
        final client = await _p2pService.ensureClientInitialized();
        await client.broadcastText(message);
      }
    } catch (e) {
      debugPrint('Unable to announce active conversation: $e');
    }
  }

  /// Share a file over the underlying P2P transport and announce it to peers.
  /// Returns the transport's file info if sharing was initiated, or null on failure.
  Future<p2p_pkg.P2pFileInfo?> sendAttachment(
    File file, {
    String? targetClientId,
  }) async {
    final roleSnapshot = _role;
    if (roleSnapshot == null) {
      _setError('Select a role before sending files.');
      return null;
    }

    try {
      if (roleSnapshot == P2pSessionRole.host) {
        final host = await _p2pService.ensureHostInitialized();
        final info = await host.broadcastFile(file);
        if (info != null) {
          final fileName = file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : file.path;
          final lower = fileName.toLowerCase();
          String mimeType = 'application/octet-stream';
          if (lower.endsWith('.png')) {
            mimeType = 'image/png';
          } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
            mimeType = 'image/jpeg';
          } else if (lower.endsWith('.gif')) {
            mimeType = 'image/gif';
          }

          // Build a ChatAttachment-shaped map so recipients can parse attachments
          // and also include transport fields needed for direct download.
          final fileMap = <String, dynamic>{
            'id': info.id,
            'filename': info.name,
            'mimeType': mimeType,
            'sizeBytes': info.size,
            'uri': '', // will be populated by downloader on recipient
            'senderHostIp': info.senderHostIp,
            'senderPort': info.senderPort,
          };

          final payload = ChatMessagePayload(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            conversationId: _activeConversationId ?? 'default',
            conversationTitle: _activeConversationTitle ?? 'Conversation',
            senderId: AppDependencies.instance.peerIdentity.id,
            senderName: AppDependencies.instance.peerIdentity.displayName,
            content: fileName,
            sentAt: DateTime.now().toUtc(),
            files: [fileMap],
          );
          await sendChatMessage(payload);
        }
        return info;
      } else {
        final client = await _p2pService.ensureClientInitialized();
        final info = await client.broadcastFile(file);
        if (info != null) {
          final fileName = file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : file.path;
          final lower = fileName.toLowerCase();
          String mimeType = 'application/octet-stream';
          if (lower.endsWith('.png')) {
            mimeType = 'image/png';
          } else if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
            mimeType = 'image/jpeg';
          } else if (lower.endsWith('.gif')) {
            mimeType = 'image/gif';
          }

          final fileMap = <String, dynamic>{
            'id': info.id,
            'filename': info.name,
            'mimeType': mimeType,
            'sizeBytes': info.size,
            'uri': '',
            'senderHostIp': info.senderHostIp,
            'senderPort': info.senderPort,
          };

          final payload = ChatMessagePayload(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            conversationId: _activeConversationId ?? 'default',
            conversationTitle: _activeConversationTitle ?? 'Conversation',
            senderId: AppDependencies.instance.peerIdentity.id,
            senderName: AppDependencies.instance.peerIdentity.displayName,
            content: fileName,
            sentAt: DateTime.now().toUtc(),
            files: [fileMap],
          );
          await sendChatMessage(payload);
        }
        return info;
      }
    } catch (e) {
      _setError('Unable to share file: $e');
      return null;
    }
  }

  // Queue a persistence task so UI flows can await metadata sync if needed.
  void _ensureConversationSynced({required String id, required String title}) {
    final store = _conversationStore;
    if (store == null) {
      return;
    }

    final sync = store
        .ensureConversationExists(id: id, title: title)
        .then<void>((_) {});
    _trackConversationSync(sync);
  }

  // Chain sync operations to serialize storage writes and expose a single
  // future that callers can await without missing in-flight updates.
  void _trackConversationSync(Future<void> future) {
    final previous = _pendingConversationSync;
    Future<void> combined;
    if (previous != null) {
      combined = previous.catchError((_) {}).then((_) => future);
    } else {
      combined = future;
    }

    final tracked = combined.catchError((_) {});
    _pendingConversationSync = tracked.whenComplete(() {
      if (identical(_pendingConversationSync, tracked)) {
        _pendingConversationSync = null;
      }
    });
  }

  void _setError(String message) {
    _errorMessage = message;
    notifyListeners();
  }
}
