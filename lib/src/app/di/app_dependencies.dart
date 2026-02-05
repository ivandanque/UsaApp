import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/database/app_database.dart';
import '../../core/models/peer_identity.dart';
import '../../core/services/chat_data_migration_service.dart';
import '../../core/services/peer_identity_service.dart';
import '../../core/utils/logger.dart';
import '../../features/chat/data/datasources/drift_chat_message_data_source.dart';
import '../../features/chat/data/datasources/chat_message_query_service.dart';
import '../../features/chat/data/datasources/drift_chat_room_data_source.dart';
import '../../features/chat/data/datasources/drift_conversation_data_source.dart';
import '../../features/chat/data/repositories/chat_repository_impl.dart';
import '../../features/chat/data/models/chat_message_model.dart';
import '../../features/chat/domain/entities/conversation.dart';
import '../../features/chat/domain/repositories/chat_repository.dart';
import '../../features/chat/domain/usecases/send_message.dart';
import '../../features/chat/domain/usecases/watch_messages.dart';
import '../../features/chat/presentation/controllers/chat_controller.dart';
import '../../core/services/notification_service.dart';
import '../../features/p2p/data/services/latency_probe_service.dart';
import '../../features/p2p/data/services/p2p_service.dart';
import '../../features/p2p/presentation/controllers/p2p_session_controller.dart';

class AppDependencies {
  AppDependencies._();

  static final AppDependencies instance = AppDependencies._();

  static const String _prefBackgroundScanningEnabled =
      'pref_background_scanning_enabled';
  static const String _prefScanCadenceSeconds = 'pref_scan_cadence_seconds';
  static const int _defaultScanCadenceSeconds = 5;

  final Logger _logger = const Logger('AppDependencies');

  // Database
  AppDatabase? _database;
  ChatDataMigrationService? _migrationService;

  // Drift data sources (SQLite-backed)
  DriftChatMessageDataSource? _driftChatMessageDataSource;
  // Long-lived query service owner for chat message streams
  ChatMessageQueryService? _chatMessageQueryService;
  DriftConversationDataSource? _driftConversationDataSource;
  DriftChatRoomDataSource? _driftChatRoomDataSource;

  late final ChatRepository _chatRepository;
  late final SendMessage _sendMessage;
  late final WatchMessages _watchMessages;
  late final P2pService _p2pService;
  late final PeerIdentityService _peerIdentityService;
  late PeerIdentity _peerIdentity;
  late final LatencyProbeService _latencyProbeService;
  Map<String, PeerIdentity> _knownPeers = <String, PeerIdentity>{};
  late final SharedPreferences _sharedPreferences;
  NotificationService? _notificationService;

  /// Initialize dependencies.
  ///
  /// Pass [executor] for testing with an in-memory database.
  /// If null, uses the default file-based SQLite database.
  Future<void> init({QueryExecutor? executor}) async {
    _logger.info('Initializing dependencies');

      final sharedPreferences = await SharedPreferences.getInstance();
      _sharedPreferences = sharedPreferences;

    // Initialize database (use provided executor for tests, or default)
    if (executor != null) {
      _database = AppDatabase(executor);
    } else {
      _database = AppDatabase();
    }

    // Run migration from SharedPreferences to SQLite
    _migrationService = ChatDataMigrationService(
      database: _database!,
      sharedPreferences: sharedPreferences,
    );
    final migrationResult = await _migrationService!.migrate();
    if (migrationResult.totalMigrated > 0) {
      _logger.info('Migration completed: $migrationResult');
    }

    // Initialize drift data sources
    // Create a long-lived query service that owns DB subscriptions for
    // chat message streams and prevents repeated open/close of queries.
    _chatMessageQueryService = ChatMessageQueryService(_database!);
    _driftChatMessageDataSource = DriftChatMessageDataSource(
      _database!,
      _chatMessageQueryService,
    );
    _driftConversationDataSource = DriftConversationDataSource(_database!);
    _driftChatRoomDataSource = DriftChatRoomDataSource(_database!);

    // Use Drift-backed data source for messaging going forward
    _chatRepository = ChatRepositoryImpl(_driftChatMessageDataSource!);
    _sendMessage = SendMessage(_chatRepository);
    _watchMessages = WatchMessages(_chatRepository);

    // Prepare P2P service (lazy initialization happens on demand)
    _p2pService = P2pService();

    _peerIdentityService = PeerIdentityService();
    _peerIdentity = await _peerIdentityService.getIdentity();
    _knownPeers = Map<String, PeerIdentity>.from(
      await _peerIdentityService.getKnownPeers(),
    );

    // Conversations are stored in SQLite via Drift; no SharedPreferences store.

    _latencyProbeService = LatencyProbeService(identity: _peerIdentity);
  }

  /// Initialize a minimal set of dependencies for fast, deterministic tests.
  /// Does not initialize the database, query service, or other long-lived
  /// resources that may schedule timers or platform channels.
  Future<void> initForTestsMinimal({
    PeerIdentity? identity,
    Map<String, PeerIdentity>? knownPeers,
    QueryExecutor? executor,
  }) async {
    _logger.info('Initializing minimal test dependencies');

    // Minimal peer identity and known peers cache
    _peerIdentity =
        identity ?? const PeerIdentity(id: 'local', displayName: 'You');
    _knownPeers = Map<String, PeerIdentity>.from(
      knownPeers ?? <String, PeerIdentity>{},
    );

    // Minimal services that do not start platform plugins eagerly
    _p2pService = P2pService();
    _latencyProbeService = LatencyProbeService(identity: _peerIdentity);
    _sharedPreferences = await SharedPreferences.getInstance();

    // Optionally create a lightweight in-memory DB + conversation store for
    // tests that need basic persistence without initializing message
    // query services that schedule timers.
    if (executor != null) {
      _database = AppDatabase(executor);
      _driftConversationDataSource = DriftConversationDataSource(_database!);
      // Provide a fake query service that does not open DB subscriptions
      // to avoid scheduling timers during tests.
      _chatMessageQueryService = _FakeChatMessageQueryService(_database!);
    }

    // Peer identity service kept for API compatibility but not required to
    // perform storage-backed operations in tests using fakes.
    _peerIdentityService = PeerIdentityService();
  }

  ChatController createChatController({required Conversation conversation}) {
    return ChatController(
      sendMessage: _sendMessage,
      watchMessages: _watchMessages,
      identity: _peerIdentity,
      conversation: conversation,
      conversationStore: _driftConversationDataSource!,
      rememberPeer: (PeerIdentity identity) async {
        await rememberPeer(identity);
      },
      knownPeers: _knownPeers,
    );
  }

  P2pService get p2pService => _p2pService;
  PeerIdentityService get peerIdentityService => _peerIdentityService;
    LatencyProbeService get latencyProbeService => _latencyProbeService;
    NotificationService get notificationService {
      _notificationService ??= NotificationService(
        plugin: FlutterLocalNotificationsPlugin(),
      );
      return _notificationService!;
    }
    bool get backgroundScanningEnabled =>
      _sharedPreferences.getBool(_prefBackgroundScanningEnabled) ?? false;
    int get scanCadenceSeconds =>
      _sharedPreferences.getInt(_prefScanCadenceSeconds) ?? _defaultScanCadenceSeconds;

  // Database and drift data sources
  AppDatabase? get database => _database;
  DriftChatMessageDataSource? get driftChatMessageDataSource =>
      _driftChatMessageDataSource;
  DriftConversationDataSource? get driftConversationDataSource =>
      _driftConversationDataSource;
  DriftChatRoomDataSource? get driftChatRoomDataSource =>
      _driftChatRoomDataSource;

  PeerIdentity get peerIdentity => _peerIdentity;
  Map<String, PeerIdentity> get knownPeers =>
      Map<String, PeerIdentity>.unmodifiable(_knownPeers);

  DriftConversationDataSource get conversationStore =>
      _driftConversationDataSource!;

  P2pSessionController createP2pSessionController() {
    return P2pSessionController(
      p2pService: _p2pService,
      conversationStore: _driftConversationDataSource,
      latencyProbeService: _latencyProbeService,
    );
  }

  /// Dispose long-lived resources created by AppDependencies.
  ///
  /// Tests should call this in `tearDownAll` to ensure subscriptions and
  /// DB connections are closed cleanly to avoid teardown races.
  Future<void> dispose() async {
    try {
      _logger.info('[AppDependencies] disposing chatMessageQueryService');
      await _chatMessageQueryService?.dispose();
      _logger.info('[AppDependencies] disposed chatMessageQueryService');
    } catch (e) {
      _logger.error(
        '[AppDependencies] error disposing chatMessageQueryService: $e',
        e,
      );
    }
    try {
      _logger.info('[AppDependencies] closing database');
      await _database?.close();
      _logger.info('[AppDependencies] database closed');
    } catch (e) {
      _logger.error('[AppDependencies] error closing database: $e', e);
    }
  }

  Future<void> updatePeerDisplayName(String displayName) async {
    final trimmed = displayName.trim();
    final effectiveName = trimmed.isEmpty
        ? _peerIdentityService.defaultDisplayName(_peerIdentity.id)
        : trimmed;
    await _peerIdentityService.setDisplayName(effectiveName);

    // Reload full identity from service so any other profile fields (name,
    // group, role, profileImage) written to SharedPreferences are reflected
    // immediately in AppDependencies.
    _peerIdentity = await _peerIdentityService.getIdentity();

    // Ensure our known peers cache and latency probe reflect the updated
    // identity object.
    _knownPeers[_peerIdentity.id] = _peerIdentity;
    _latencyProbeService.updateIdentity(_peerIdentity);
  }

  Future<void> rememberPeer(PeerIdentity identity) async {
    await _peerIdentityService.rememberPeer(identity);
    _knownPeers[identity.id] = identity;
  }

  Future<void> setBackgroundScanningEnabled(bool enabled) async {
    await _sharedPreferences.setBool(
      _prefBackgroundScanningEnabled,
      enabled,
    );
  }

  Future<void> setScanCadenceSeconds(int seconds) async {
    await _sharedPreferences.setInt(
      _prefScanCadenceSeconds,
      seconds,
    );
  }

  /// Initialize the platform-specific parts of `NotificationService`.
  ///
  /// Call this during app runtime startup. Tests should avoid calling
  /// this so that platform channels are not invoked in unit tests.
  Future<void> initializeNotificationService() async {
    _notificationService ??= NotificationService(
      plugin: FlutterLocalNotificationsPlugin(),
    );
    if (!kIsWeb) {
      await _notificationService!.initialize();
    }
  }
}

// Test helper: a fake ChatMessageQueryService that avoids creating DB
// subscriptions and simply exposes an empty broadcast stream per conversation.
class _FakeChatMessageQueryService extends ChatMessageQueryService {
  _FakeChatMessageQueryService(super.db);

  @override
  Stream<List<ChatMessageModel>> watch(String conversationId) {
    return Stream<List<ChatMessageModel>>.value(
      const <ChatMessageModel>[],
    ).asBroadcastStream();
  }

  @override
  Future<void> dispose() async {
    // No-op for fake
    return;
  }
}
