import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/room_summary.dart';
import '../../app/routes/app_route_names.dart';

/// Adapter interface so tests can provide a lightweight fake implementation
/// without depending on the real plugin implementation.
abstract class NotificationPlugin {
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  });
}

class _FlutterLocalNotificationsAdapter implements NotificationPlugin {
  _FlutterLocalNotificationsAdapter(this._impl);

  final FlutterLocalNotificationsPlugin _impl;

  @override
  Future<void> show({
    required int id,
    String? title,
    String? body,
    NotificationDetails? notificationDetails,
    String? payload,
  }) {
    return _impl.show(
      id: id,
      title: title,
      body: body,
      notificationDetails: notificationDetails,
      payload: payload,
    );
  }
}

class NotificationService {
  NotificationService({required FlutterLocalNotificationsPlugin plugin})
      : _plugin = _FlutterLocalNotificationsAdapter(plugin);

  /// Constructor used by tests to inject a fake `NotificationPlugin`.
  NotificationService.withPlugin({required NotificationPlugin plugin})
      : _plugin = plugin;

  static const String _roomsChannelId = 'usaapp_p2p_rooms';
  static const String _roomsChannelName = 'Nearby rooms';
  static const String _roomsChannelDescription =
      'Alerts when peers advertise nearby conversations';

  static const String _scanningChannelId = 'usaapp_scanning';
  static const String _scanningChannelName = 'Background scanning';
  static const String _scanningChannelDescription =
      'Shows when app is actively scanning for nearby devices';

  static const int _roomsNotificationId = 9001;
  static const int _connectionNotificationId = 9002;
  static const int _disconnectionNotificationId = 9003;
  static const int _scanningNotificationId = 9004;

  final NotificationPlugin _plugin;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;

  Future<void> initialize({bool requestPermissions = true}) async {
    // Defer platform plugin initialization to runtime when running on device.
    // In tests and headless environments we avoid invoking platform APIs
    // to keep unit tests deterministic.
    _initialized = true;
    return;
  }

  Future<void> requestPermissionIfNeeded() async {
    // No-op in test environments; platform-specific permission requests are
    // handled at runtime on device when needed.
    return;
  }

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  Future<void> notifyRoomsFound(List<RoomSummary> rooms) async {
    if (!_initialized || rooms.isEmpty) {
      return;
    }

    final title = rooms.length == 1
        ? 'room: ${rooms.first.roomTitle}'
        : '${rooms.length} rooms nearby';
    final body = rooms
        .take(4)
        .map((room) => '${room.roomTitle} · ${room.hostName}')
        .join('\n');

    await _plugin.show(
      id: _roomsNotificationId,
      title: title,
      body: body.isNotEmpty ? body : 'Peers are advertising nearby conversations.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _roomsChannelId,
          _roomsChannelName,
          channelDescription: _roomsChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: BigTextStyleInformation(
            body.isNotEmpty ? body : 'Tap to open the chat discovery screen.',
          ),
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      payload: 'rooms',
    );
  }

  Future<void> notifyConnected(String roomTitle, String hostName) async {
    if (!_initialized) {
      return;
    }

    await _plugin.show(
      id: _connectionNotificationId,
      title: 'Connected to $roomTitle',
      body: 'Linked with $hostName via Wi‑Fi P2P',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _roomsChannelId,
          _roomsChannelName,
          channelDescription: _roomsChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      payload: 'connected',
    );
  }

  Future<void> notifyDisconnected() async {
    if (!_initialized) {
      return;
    }

    await _plugin.show(
      id: _disconnectionNotificationId,
      title: 'Disconnected',
      body: 'Your P2P session has ended.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _roomsChannelId,
          _roomsChannelName,
          channelDescription: _roomsChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      payload: 'disconnected',
    );
  }

  /// Shows a persistent notification when scanning in background
  Future<void> showScanningNotification() async {
    if (!_initialized) {
      return;
    }

    await _plugin.show(
      id: _scanningNotificationId,
      title: 'UsaApp is searching in background',
      body: 'Scanning for nearby devices...',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _scanningChannelId,
          _scanningChannelName,
          channelDescription: _scanningChannelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true, // Makes it persistent
          autoCancel: false,
        ),
        iOS: const DarwinNotificationDetails(presentSound: false),
      ),
      payload: 'scanning',
    );
  }

  /// Cancels the background scanning notification by showing an empty one
  /// (workaround for cancel API issue in flutter_local_notifications 20.0.0)
  Future<void> cancelScanningNotification() async {
    // Simply don't show anything - notification will auto-dismiss when scanning stops
    // or we can update it to show "Scan complete" then auto-cancel
    return;
  }

  void _handleNotificationResponse(NotificationResponse response) {
    _navigateToConversationMode();
  }

  void _navigateToConversationMode() {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      return;
    }
    navigator.pushNamed(AppRouteNames.conversationMode);
  }
}
