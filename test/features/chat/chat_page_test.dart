import 'dart:async';

// Use minimal test dependencies instead of initializing the full DB.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/core/database/app_database.dart';
import 'package:usaapp/src/features/chat/data/datasources/drift_conversation_data_source.dart';
import 'package:usaapp/src/features/chat/domain/entities/conversation.dart';
import 'package:usaapp/src/features/chat/domain/entities/chat_message.dart';
import 'package:usaapp/src/features/chat/domain/repositories/chat_repository.dart';
import 'package:usaapp/src/features/chat/domain/usecases/send_message.dart';
import 'package:usaapp/src/features/chat/domain/usecases/watch_messages.dart';
import 'package:usaapp/src/features/chat/presentation/controllers/chat_controller.dart';
import 'package:usaapp/src/features/chat/presentation/pages/chat_page.dart';
import 'package:usaapp/src/core/models/peer_identity.dart';
import 'package:usaapp/src/features/p2p/presentation/controllers/p2p_session_controller.dart';
import '../../test_helpers/test_fakes.dart';
import 'package:drift/native.dart';

void main() {
  late Conversation conversation;
  late ChatController testController;
  late P2pSessionController testP2pController;
  late InMemoryChatRepository inMemoryRepo;
  AppDatabase? testDb;

  // Use shared FakeConversationStore from test helpers.

  // Use shared FakeP2pSessionController from test helpers.

  Future<void> waitForText(
    WidgetTester tester,
    String text, {
    Duration timeout = const Duration(seconds: 2),
  }) async {
    // increase default timeout slightly for CI/flaky environments
    timeout = timeout == const Duration(seconds: 2)
        ? const Duration(seconds: 3)
        : timeout;
    final end = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 50));
      if (find.text(text).evaluate().isNotEmpty) return;
    }
  }

  // Shared timeout for widget tests to avoid long 10-minute default runs.
  const testTimeout = Timeout(Duration(minutes: 3));

  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    // Create a per-test in-memory DB and conversation store to avoid global
    // AppDependencies initialization that schedules background timers.
    final db = AppDatabase(NativeDatabase.memory());
    final store = DriftConversationDataSource(db);
    conversation = await store.createConversation('Test Conversation');

    // Use an in-memory ChatRepository to mock send/watch behavior and avoid
    // DB-backed watchers causing teardown races.
    inMemoryRepo = InMemoryChatRepository();
    final sendMessage = SendMessage(inMemoryRepo);
    final watchMessages = WatchMessages(inMemoryRepo);

    final localIdentity = const PeerIdentity(id: 'local', displayName: 'You');
    // Patch InMemoryChatRepository to always use this identity for senderId/sender.
    inMemoryRepo.localIdentity = localIdentity;

    testP2pController = FakeP2pSessionController();

    testController = ChatController(
      sendMessage: sendMessage,
      watchMessages: watchMessages,
      identity: localIdentity,
      conversation: conversation,
      conversationStore: store,
      rememberPeer: (PeerIdentity identity) async {},
      knownPeers: {},
    );
    await testController.start();

    // Record DB so we can close it in tearDown.
    testDb = db;
  });

  tearDown(() async {
    try {
      testController.dispose();
    } catch (_) {}
    try {
      testP2pController.dispose();
    } catch (_) {}
    try {
      await inMemoryRepo.dispose();
    } catch (_) {}
    try {
      await testDb?.close();
    } catch (_) {}
  });

  group('ChatPage', () {
    testWidgets('smoke: can pump a minimal title widget', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Text(conversation.title))),
      );
      expect(find.text('Test Conversation'), findsOneWidget);
    }, timeout: testTimeout);
    group('initial state', () {
      testWidgets('displays conversation title in app bar', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        expect(find.text('Test Conversation'), findsOneWidget);
      }, timeout: testTimeout);

      testWidgets('displays empty state message', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        expect(
          find.text('Start a conversation by sending a message.'),
          findsOneWidget,
        );
      }, timeout: testTimeout);

      testWidgets('displays message input field', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        expect(find.byType(TextField), findsOneWidget);
      }, timeout: testTimeout);

      testWidgets('displays send button', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.send), findsOneWidget);
      }, timeout: testTimeout);
    });

    group('sending messages', () {
      testWidgets('displays sent message in chat', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        // Allow controller to start
        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField), 'Hello, World!');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await waitForText(tester, 'Hello, World!');

        expect(find.text('Hello, World!'), findsOneWidget);
      }, timeout: testTimeout);

      testWidgets('clears input field after sending', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField), 'Test message');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await waitForText(tester, 'Test message');

        final textField = tester.widget<TextField>(find.byType(TextField));
        expect(textField.controller?.text, isEmpty);
      }, timeout: testTimeout);

      testWidgets('displays sender label as You for local messages', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField), 'My message');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await waitForText(tester, 'My message');

        expect(find.text('You'), findsOneWidget);
      }, timeout: testTimeout);
    });

    group('multiple messages', () {
      testWidgets('displays first message', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField), 'First message');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await waitForText(tester, 'First message');

        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField), 'Second message');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await waitForText(tester, 'Second message');
        expect(find.text('First message'), findsOneWidget);
      }, timeout: testTimeout);

      testWidgets('displays second message', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        await tester.enterText(find.byType(TextField), 'First message');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await waitForText(tester, 'First message');
        await tester.enterText(find.byType(TextField), 'Second message');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.text('Second message'), findsOneWidget);
      }, timeout: testTimeout);
    });

    group('profile avatars', () {
      testWidgets('displays profile avatar for sent message', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: ChatPage(
              conversation: conversation,
              controller: testController,
              p2pController: testP2pController,
              testPeerIdentity: const PeerIdentity(
                id: 'local',
                displayName: 'You',
              ),
            ),
          ),
        );

        await tester.pump(const Duration(milliseconds: 50));
        await tester.enterText(find.byType(TextField), 'Test');
        await tester.tap(find.byIcon(Icons.send));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 50));

        expect(find.byType(CircleAvatar), findsWidgets);
      }, timeout: testTimeout);
    });
  });
}

// Simple in-memory ChatRepository used by tests to mock message sending and
// watching. Keeps per-conversation lists and stream controllers.
class InMemoryChatRepository implements ChatRepository {
  final Map<String, List<ChatMessage>> _store = {};
  final Map<String, StreamController<List<ChatMessage>>> _controllers = {};
  PeerIdentity? localIdentity;

  StreamController<List<ChatMessage>> _controllerFor(String convo) {
    return _controllers.putIfAbsent(
      convo,
      () => StreamController<List<ChatMessage>>.broadcast(),
    );
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _controllerFor(conversationId).stream;
  }

  @override
  Future<void> sendMessage(String conversationId, ChatMessage message) async {
    // Always use the injected local identity for sender fields.
    final identity = localIdentity;
    final patched = identity == null
        ? message
        : message.copyWith(senderId: identity.id, sender: identity.displayName);
    final list = _store.putIfAbsent(conversationId, () => <ChatMessage>[]);
    list.add(patched);
    _controllerFor(conversationId).add(List<ChatMessage>.unmodifiable(list));
  }

  @override
  Future<void> clearConversation(String conversationId) async {
    _store.remove(conversationId);
    _controllerFor(conversationId).add(const <ChatMessage>[]);
  }

  // No-op for widget tests: closing controllers can hang if listeners are still active.
  Future<void> dispose() async {
    _controllers.clear();
    _store.clear();
  }
}
