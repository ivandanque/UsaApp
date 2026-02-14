import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usaapp/src/core/database/app_database.dart';
import 'package:usaapp/src/core/services/chat_data_migration_service.dart';
import 'package:usaapp/src/features/chat/data/models/chat_message_model.dart';
import 'package:usaapp/src/features/chat/data/models/chat_room_model.dart';
import 'package:usaapp/src/features/chat/domain/entities/conversation.dart';

void main() {
  late AppDatabase db;
  late SharedPreferences prefs;
  late ChatDataMigrationService migrationService;

  setUp(() async {
    // Use in-memory database for testing
    db = AppDatabase(NativeDatabase.memory());

    // Set up mock SharedPreferences
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    migrationService = ChatDataMigrationService(
      database: db,
      sharedPreferences: prefs,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('ChatDataMigrationService', () {
    test('should report not migrated initially', () {
      expect(migrationService.isMigrationComplete, false);
    });

    test('should migrate empty data successfully', () async {
      final result = await migrationService.migrate();

      expect(result.success, true);
      expect(result.conversationsMigrated, 0);
      expect(result.messagesMigrated, 0);
      expect(result.roomsMigrated, 0);
      expect(migrationService.isMigrationComplete, true);
    });

    test('should skip if already migrated', () async {
      // First migration
      await migrationService.migrate();

      // Second migration should be skipped
      final result = await migrationService.migrate();

      expect(result.alreadyMigrated, true);
      expect(result.totalMigrated, 0);
    });

    test('should migrate conversations from SharedPreferences', () async {
      // Set up legacy data
      final now = DateTime.now().toUtc();
      final conversations = [
        Conversation(
          id: 'conv-1',
          title: 'Test Conversation',
          createdAt: now,
          updatedAt: now,
        ),
        Conversation(
          id: 'conv-2',
          title: 'Another Conversation',
          createdAt: now,
          updatedAt: now,
        ),
      ];
      await prefs.setString(
        'conversation_store_v1',
        jsonEncode(conversations.map((c) => c.toJson()).toList()),
      );

      // Run migration
      final result = await migrationService.migrate();

      expect(result.success, true);
      expect(result.conversationsMigrated, 2);

      // Verify data in SQLite
      final migrated = await db.getConversationById('conv-1');
      expect(migrated, isNotNull);
      expect(migrated!.title, 'Test Conversation');
    });

    test('should migrate messages from SharedPreferences', () async {
      // Set up legacy conversations
      final now = DateTime.now().toUtc();
      await prefs.setString(
        'conversation_store_v1',
        jsonEncode([
          Conversation(
            id: 'conv-1',
            title: 'Test',
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ]),
      );

      // Set up legacy messages
      final messages = [
        ChatMessageModel(
          id: 'msg-1',
          conversationId: 'conv-1',
          senderId: 'user-1',
          sender: 'Alice',
          content: 'Hello!',
          sentAt: now,
        ),
        ChatMessageModel(
          id: 'msg-2',
          conversationId: 'conv-1',
          senderId: 'user-2',
          sender: 'Bob',
          content: 'Hi there!',
          sentAt: now.add(const Duration(seconds: 1)),
        ),
      ];
      await prefs.setString(
        'chat_messages_v1_conv-1',
        jsonEncode(messages.map((m) => m.toJson()).toList()),
      );

      // Run migration
      final result = await migrationService.migrate();

      expect(result.success, true);
      expect(result.messagesMigrated, 2);

      // Verify data in SQLite
      final migratedMessages = await db.watchMessages('conv-1').first;
      expect(migratedMessages.length, 2);
      expect(migratedMessages[0].content, 'Hello!');
    });

    test('should migrate chat rooms from SharedPreferences', () async {
      // Set up legacy rooms
      final now = DateTime.now().toUtc();
      final rooms = [
        ChatRoomModel.createPublicRoom(
          id: 'room-1',
          name: 'Public Room',
          description: 'A public room',
          ownerId: 'user-1',
          createdAt: now,
          updatedAt: now,
        ),
        ChatRoomModel.createPrivateRoom(
          id: 'room-2',
          name: 'Private Room',
          description: 'A private room',
          ownerId: 'user-1',
          password: 'secret123',
          createdAt: now,
          updatedAt: now,
        ),
      ];
      await prefs.setString(
        'chat_room_store_v1',
        jsonEncode(rooms.map((r) => r.toJson()).toList()),
      );

      // Run migration
      final result = await migrationService.migrate();

      expect(result.success, true);
      expect(result.roomsMigrated, 2);

      // Verify data in SQLite
      final migratedRoom = await db.getRoomById('room-1');
      expect(migratedRoom, isNotNull);
      expect(migratedRoom!.name, 'Public Room');
      expect(migratedRoom.isPrivate, false);

      final privateRoom = await db.getRoomById('room-2');
      expect(privateRoom, isNotNull);
      expect(privateRoom!.isPrivate, true);
      expect(privateRoom.passwordHash, isNotNull);
    });

    test('should clean up SharedPreferences after migration', () async {
      // Set up legacy data
      final now = DateTime.now().toUtc();
      await prefs.setString(
        'conversation_store_v1',
        jsonEncode([
          Conversation(
            id: 'conv-1',
            title: 'Test',
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ]),
      );
      await prefs.setString(
        'chat_messages_v1_conv-1',
        jsonEncode([
          ChatMessageModel(
            id: 'msg-1',
            conversationId: 'conv-1',
            senderId: 'user-1',
            sender: 'Alice',
            content: 'Hello!',
            sentAt: now,
          ).toJson(),
        ]),
      );
      await prefs.setString(
        'chat_room_store_v1',
        jsonEncode([
          ChatRoomModel.createPublicRoom(
            id: 'room-1',
            name: 'Test',
            description: 'Test',
            ownerId: 'user-1',
            createdAt: now,
            updatedAt: now,
          ).toJson(),
        ]),
      );

      // Run migration
      await migrationService.migrate();

      // Verify SharedPreferences is cleaned up
      expect(prefs.getString('conversation_store_v1'), isNull);
      expect(prefs.getString('chat_messages_v1_conv-1'), isNull);
      expect(prefs.getString('chat_room_store_v1'), isNull);
    });

    test('should handle corrupted data gracefully', () async {
      // Set up corrupted data
      await prefs.setString('conversation_store_v1', 'not valid json');
      await prefs.setString('chat_messages_v1_conv-1', '{invalid}');
      await prefs.setString('chat_room_store_v1', '123');

      // Run migration - should not throw
      final result = await migrationService.migrate();

      expect(result.conversationsMigrated, 0);
      expect(result.messagesMigrated, 0);
      expect(result.roomsMigrated, 0);
    });

    test('should allow reset of migration status', () async {
      await migrationService.migrate();
      expect(migrationService.isMigrationComplete, true);

      await migrationService.resetMigrationStatus();
      expect(migrationService.isMigrationComplete, false);
    });
  });

  group('AppDatabase', () {
    test('should insert and retrieve conversations', () async {
      final now = DateTime.now().toUtc();
      await db.upsertConversation(
        ConversationEntry(
          id: 'conv-1',
          title: 'Test',
          isPrivate: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await db.getConversationById('conv-1');
      expect(result, isNotNull);
      expect(result!.title, 'Test');
    });

    test('should watch conversations reactively', () async {
      final now = DateTime.now().toUtc();
      final emissions = <List<ConversationEntry>>[];
      final subscription = db.watchAllConversations().listen(emissions.add);

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await db.upsertConversation(
        ConversationEntry(
          id: 'conv-1',
          title: 'First',
          isPrivate: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));

      await db.upsertConversation(
        ConversationEntry(
          id: 'conv-2',
          title: 'Second',
          isPrivate: false,
          createdAt: now,
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
      );

      await Future<void>.delayed(const Duration(milliseconds: 50));
      await subscription.cancel();

      // Should have received multiple emissions as data changed
      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last.length, 2);
    });

    test('should insert and retrieve messages', () async {
      final now = DateTime.now().toUtc();

      // Insert conversation first (foreign key)
      await db.upsertConversation(
        ConversationEntry(
          id: 'conv-1',
          title: 'Test',
          isPrivate: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.upsertMessage(
        ChatMessageEntry(
          id: 'msg-1',
          conversationId: 'conv-1',
          senderId: 'user-1',
          sender: 'Alice',
          content: 'Hello!',
          sentAt: now,
          attachments: '[]',
        ),
      );

      final messages = await db.watchMessages('conv-1').first;
      expect(messages.length, 1);
      expect(messages[0].content, 'Hello!');
    });

    test('should paginate messages', () async {
      final now = DateTime.now().toUtc();

      await db.upsertConversation(
        ConversationEntry(
          id: 'conv-1',
          title: 'Test',
          isPrivate: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      // Insert 10 messages
      for (var i = 0; i < 10; i++) {
        await db.upsertMessage(
          ChatMessageEntry(
            id: 'msg-$i',
            conversationId: 'conv-1',
            senderId: 'user-1',
            sender: 'Alice',
            content: 'Message $i',
            sentAt: now.add(Duration(seconds: i)),
            attachments: '[]',
          ),
        );
      }

      // Get first page (5 messages, most recent first)
      final page1 = await db
          .watchMessagesPaginated('conv-1', limit: 5, offset: 0)
          .first;
      expect(page1.length, 5);
      expect(page1[0].content, 'Message 9'); // Most recent first

      // Get second page
      final page2 = await db
          .watchMessagesPaginated('conv-1', limit: 5, offset: 5)
          .first;
      expect(page2.length, 5);
      expect(page2[0].content, 'Message 4');
    });

    test('should search messages by content', () async {
      final now = DateTime.now().toUtc();

      await db.upsertConversation(
        ConversationEntry(
          id: 'conv-1',
          title: 'Test',
          isPrivate: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.upsertMessage(
        ChatMessageEntry(
          id: 'msg-1',
          conversationId: 'conv-1',
          senderId: 'user-1',
          sender: 'Alice',
          content: 'Hello world!',
          sentAt: now,
          attachments: '[]',
        ),
      );

      await db.upsertMessage(
        ChatMessageEntry(
          id: 'msg-2',
          conversationId: 'conv-1',
          senderId: 'user-1',
          sender: 'Alice',
          content: 'Goodbye!',
          sentAt: now.add(const Duration(seconds: 1)),
          attachments: '[]',
        ),
      );

      final results = await db.searchMessages('Hello');
      expect(results.length, 1);
      expect(results[0].content, 'Hello world!');
    });

    test('should insert and retrieve chat rooms', () async {
      final now = DateTime.now().toUtc();

      await db.upsertRoom(
        ChatRoomEntry(
          id: 'room-1',
          name: 'Test Room',
          description: 'A test room',
          ownerId: 'user-1',
          isPrivate: false,
          memberIds: '["user-1", "user-2"]',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final result = await db.getRoomById('room-1');
      expect(result, isNotNull);
      expect(result!.name, 'Test Room');
      expect(result.memberIdsList, ['user-1', 'user-2']);
    });

    test('should delete conversation and its messages', () async {
      final now = DateTime.now().toUtc();

      await db.upsertConversation(
        ConversationEntry(
          id: 'conv-1',
          title: 'Test',
          isPrivate: false,
          createdAt: now,
          updatedAt: now,
        ),
      );

      await db.upsertMessage(
        ChatMessageEntry(
          id: 'msg-1',
          conversationId: 'conv-1',
          senderId: 'user-1',
          sender: 'Alice',
          content: 'Hello!',
          sentAt: now,
          attachments: '[]',
        ),
      );

      await db.deleteConversation('conv-1');

      final conv = await db.getConversationById('conv-1');
      expect(conv, isNull);

      final messages = await db.watchMessages('conv-1').first;
      expect(messages, isEmpty);
    });
  });
}
