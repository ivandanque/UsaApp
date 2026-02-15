import 'dart:io' show Platform;
import 'dart:typed_data';

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

  Future<void> cancel({required int id});

  Future<bool?> initialize({
    required InitializationSettings settings,
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
  });

  /// Request notification permission on Android 13+.
  /// Returns `true` if granted, `false` otherwise, `null` if unsupported.
  Future<bool?> requestPermission();
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

  @override
  Future<void> cancel({required int id}) {
    return _impl.cancel(id: id);
  }

  @override
  Future<bool?> initialize({
    required InitializationSettings settings,
    void Function(NotificationResponse)? onDidReceiveNotificationResponse,
  }) {
    return _impl.initialize(
      settings: settings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  @override
  Future<bool?> requestPermission() async {
    final androidPlugin = _impl
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (androidPlugin == null) return null;
    return androidPlugin.requestNotificationsPermission();
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

  static const String _chatEventsChannelId = 'usaapp_chat_events';
  static const String _chatEventsChannelName = 'Chat events';
  static const String _chatEventsChannelDescription =
      'Notifications when someone joins, leaves, or rejoins the chat';

  static const int _roomsNotificationId = 9001;
  static const int _connectionNotificationId = 9002;
  static const int _disconnectionNotificationId = 9003;
  static const int _scanningNotificationId = 9004;
  // Chat event notification IDs start at 9100 and auto-increment
  // to allow multiple visible notifications.
  int _nextChatEventNotificationId = 9100;

  /// Default vibration pattern: 0ms delay, 250ms vibrate, 100ms pause,
  /// 250ms vibrate.
  static final Int64List _vibrationPattern = Int64List.fromList(<int>[
    0,
    250,
    100,
    250,
  ]);

  final NotificationPlugin _plugin;
  GlobalKey<NavigatorState>? _navigatorKey;
  bool _initialized = false;

  /// Callback that returns whether vibration is enabled in settings.
  /// Defaults to `true` when not set.
  bool Function() vibrationEnabled = () => true;

  Future<void> initialize({bool requestPermissions = true}) async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestSoundPermission: true,
      requestBadgePermission: true,
      requestAlertPermission: true,
    );
    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );

    _initialized = true;

    if (requestPermissions) {
      await requestPermissionIfNeeded();
    }
  }

  Future<void> requestPermissionIfNeeded() async {
    try {
      if (Platform.isAndroid) {
        await _plugin.requestPermission();
      }
    } catch (_) {
      // Swallow on platforms that don't support the call (tests, desktop).
    }
  }

  void setNavigatorKey(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  // ---------------------------------------------------------------------------
  // Feature 1 — Room discovery notifications
  // ---------------------------------------------------------------------------

  /// Notifies the user that at least one host has been found nearby.
  ///
  /// Per the spec the title is always "A host has been found" regardless of
  /// the number of discovered rooms.  The notification body lists up to 4
  /// rooms for additional context.
  Future<void> notifyRoomsFound(List<RoomSummary> rooms) async {
    if (!_initialized || rooms.isEmpty) {
      return;
    }

    const title = 'A host has been found';
    final body = rooms
        .take(4)
        .map((room) => '${room.roomTitle} · ${room.hostName}')
        .join('\n');

    final useVibration = vibrationEnabled();

    await _plugin.show(
      id: _roomsNotificationId,
      title: title,
      body: body.isNotEmpty ? body : 'Tap to open the chat discovery screen.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _roomsChannelId,
          _roomsChannelName,
          channelDescription: _roomsChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          enableVibration: useVibration,
          vibrationPattern: useVibration ? _vibrationPattern : null,
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
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _roomsChannelId,
          _roomsChannelName,
          channelDescription: _roomsChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
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
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _roomsChannelId,
          _roomsChannelName,
          channelDescription: _roomsChannelDescription,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(presentSound: true),
      ),
      payload: 'disconnected',
    );
  }

  /// Shows a persistent notification when scanning in background.
  Future<void> showScanningNotification() async {
    if (!_initialized) {
      return;
    }

    await _plugin.show(
      id: _scanningNotificationId,
      title: 'Searching for nearby hosts',
      body: 'Scanning for nearby devices…',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _scanningChannelId,
          _scanningChannelName,
          channelDescription: _scanningChannelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
        ),
        iOS: DarwinNotificationDetails(presentSound: false),
      ),
      payload: 'scanning',
    );
  }

  /// Cancels the background scanning notification.
  Future<void> cancelScanningNotification() async {
    if (!_initialized) return;
    await _plugin.cancel(id: _scanningNotificationId);
  }

  // ---------------------------------------------------------------------------
  // Feature 2 — Peer join / leave / rejoin chat notifications
  // ---------------------------------------------------------------------------

  /// Shows a notification that [displayName] has joined the chat.
  ///
  /// If [profileImageBase64] is provided it will be displayed when the
  /// notification is expanded.
  Future<void> notifyPeerJoined(
    String displayName, {
    String? profileImageBase64,
  }) {
    return _showChatEventNotification(
      title: '$displayName has joined the chat.',
      profileImageBase64: profileImageBase64,
      payload: 'peer_joined',
    );
  }

  /// Shows a notification that [displayName] has left the chat.
  Future<void> notifyPeerLeft(
    String displayName, {
    String? profileImageBase64,
  }) {
    return _showChatEventNotification(
      title: '$displayName has left the chat.',
      profileImageBase64: profileImageBase64,
      payload: 'peer_left',
    );
  }

  /// Shows a notification that [displayName] has rejoined the chat.
  Future<void> notifyPeerRejoined(
    String displayName, {
    String? profileImageBase64,
  }) {
    return _showChatEventNotification(
      title: '$displayName has rejoined the chat.',
      profileImageBase64: profileImageBase64,
      payload: 'peer_rejoined',
    );
  }

  Future<void> _showChatEventNotification({
    required String title,
    String? profileImageBase64,
    required String payload,
  }) async {
    if (!_initialized) return;

    StyleInformation? styleInfo;
    if (profileImageBase64 != null && profileImageBase64.isNotEmpty) {
      try {
        styleInfo = BigPictureStyleInformation(
          ByteArrayAndroidBitmap.fromBase64String(profileImageBase64),
          contentTitle: title,
          summaryText: title,
          hideExpandedLargeIcon: true,
        );
      } catch (_) {
        // If decoding fails, fall back to default style.
      }
    }

    final id = _nextChatEventNotificationId++;
    // Wrap around to avoid unbounded growth.
    if (_nextChatEventNotificationId > 9199) {
      _nextChatEventNotificationId = 9100;
    }

    await _plugin.show(
      id: id,
      title: title,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _chatEventsChannelId,
          _chatEventsChannelName,
          channelDescription: _chatEventsChannelDescription,
          importance: Importance.high,
          priority: Priority.high,
          styleInformation: styleInfo,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
      payload: payload,
    );
  }

  // ---------------------------------------------------------------------------
  // Notification tap handling
  // ---------------------------------------------------------------------------

  void _handleNotificationResponse(NotificationResponse response) {
    _navigateToConversationMode();
  }

  void _navigateToConversationMode() {
    final navigator = _navigatorKey?.currentState;
    if (navigator == null) {
      return;
    }

    // Peek at the top-most route name without popping anything.
    String? topRouteName;
    navigator.popUntil((route) {
      topRouteName = route.settings.name;
      return true; // don't actually pop
    });

    // If the conversation page is already on top, just let the OS
    // bring the app to the foreground — no new route needed.
    if (topRouteName == AppRouteNames.conversationMode) {
      return;
    }

    navigator.pushNamed(AppRouteNames.conversationMode);
  }
}
