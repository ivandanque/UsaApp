import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../database/app_database.dart';
import '../../features/chat/data/models/chat_message_model.dart';
import '../../features/chat/data/models/chat_room_model.dart';
import '../../features/chat/domain/entities/conversation.dart';

/// Service responsible for migrating data from SharedPreferences to SQLite.
///
/// This is a one-time migration that:
/// 1. Reads all existing data from SharedPreferences
/// 2. Inserts it into the SQLite database
/// 3. Clears the SharedPreferences keys after successful migration
///
/// The migration is idempotent - running it multiple times is safe.
class ChatDataMigrationService {
  ChatDataMigrationService({
    required AppDatabase database,
    required SharedPreferences sharedPreferences,
  }) : _db = database,
       _prefs = sharedPreferences;

  final AppDatabase _db;
  final SharedPreferences _prefs;

  // SharedPreferences keys from the old implementation
  static const String _conversationStoreKey = 'conversation_store_v1';
  static const String _chatMessagesPrefix = 'chat_messages_v1_';
  static const String _chatRoomStoreKey = 'chat_room_store_v1';
  static const String _migrationCompleteKey = 'chat_data_migration_v1_complete';

  /// Check if migration has already been completed.
  bool get isMigrationComplete =>
      _prefs.getBool(_migrationCompleteKey) ?? false;

  /// Run the migration from SharedPreferences to SQLite.
  ///
  /// Returns a [MigrationResult] with statistics about what was migrated.
  /// If migration was already completed, returns early with zeros.
  Future<MigrationResult> migrate() async {
    if (isMigrationComplete) {
      return const MigrationResult(
        alreadyMigrated: true,
        conversationsMigrated: 0,
        messagesMigrated: 0,
        roomsMigrated: 0,
      );
    }

    var conversationsMigrated = 0;
    var messagesMigrated = 0;
    var roomsMigrated = 0;
    final errors = <String>[];

    try {
      // 1. Migrate conversations
      final conversationsResult = await _migrateConversations();
      conversationsMigrated = conversationsResult.count;
      if (conversationsResult.error != null) {
        errors.add(conversationsResult.error!);
      }

      // 2. Migrate messages for each conversation
      final messagesResult = await _migrateMessages();
      messagesMigrated = messagesResult.count;
      if (messagesResult.error != null) {
        errors.add(messagesResult.error!);
      }

      // 3. Migrate chat rooms
      final roomsResult = await _migrateChatRooms();
      roomsMigrated = roomsResult.count;
      if (roomsResult.error != null) {
        errors.add(roomsResult.error!);
      }

      // 4. Mark migration as complete
      await _prefs.setBool(_migrationCompleteKey, true);

      // 5. Clean up old SharedPreferences data
      await _cleanupOldData();

      return MigrationResult(
        conversationsMigrated: conversationsMigrated,
        messagesMigrated: messagesMigrated,
        roomsMigrated: roomsMigrated,
        errors: errors.isEmpty ? null : errors,
      );
    } catch (e) {
      return MigrationResult(
        conversationsMigrated: conversationsMigrated,
        messagesMigrated: messagesMigrated,
        roomsMigrated: roomsMigrated,
        errors: [...errors, 'Migration failed: $e'],
      );
    }
  }

  Future<_MigrationStepResult> _migrateConversations() async {
    try {
      final raw = _prefs.getString(_conversationStoreKey);
      if (raw == null || raw.isEmpty) {
        return const _MigrationStepResult(count: 0);
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const _MigrationStepResult(
          count: 0,
          error: 'Invalid conversations format',
        );
      }

      var count = 0;
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            final conversation = Conversation.fromJson(item);
            await _db.upsertConversation(
              ConversationEntry(
                id: conversation.id,
                title: conversation.title,
                createdAt: conversation.createdAt,
                updatedAt: conversation.updatedAt,
              ),
            );
            count++;
          } catch (_) {
            // Skip invalid entries
          }
        }
      }

      return _MigrationStepResult(count: count);
    } catch (e) {
      return _MigrationStepResult(count: 0, error: 'Conversations error: $e');
    }
  }

  Future<_MigrationStepResult> _migrateMessages() async {
    try {
      var totalCount = 0;

      // Find all message keys
      final allKeys = _prefs.getKeys();
      final messageKeys = allKeys.where(
        (key) => key.startsWith(_chatMessagesPrefix),
      );

      for (final key in messageKeys) {
        final raw = _prefs.getString(key);

        if (raw == null || raw.isEmpty) continue;

        try {
          final decoded = jsonDecode(raw);
          if (decoded is! List) continue;

          final messages = <ChatMessageEntry>[];
          for (final item in decoded) {
            if (item is Map<String, dynamic>) {
              try {
                final model = ChatMessageModel.fromJson(item);
                messages.add(
                  ChatMessageEntry(
                    id: model.id,
                    conversationId: model.conversationId,
                    senderId: model.senderId,
                    sender: model.sender,
                    content: model.content,
                    sentAt: model.sentAt,
                    attachments: jsonEncode(
                      model.attachments.map((a) => a.toJson()).toList(),
                    ),
                  ),
                );
              } catch (_) {
                // Skip invalid entries
              }
            }
          }

          if (messages.isNotEmpty) {
            await _db.insertMessagesBatch(messages);
            totalCount += messages.length;
          }
        } catch (_) {
          // Skip corrupted conversation data
        }
      }

      return _MigrationStepResult(count: totalCount);
    } catch (e) {
      return _MigrationStepResult(count: 0, error: 'Messages error: $e');
    }
  }

  Future<_MigrationStepResult> _migrateChatRooms() async {
    try {
      final raw = _prefs.getString(_chatRoomStoreKey);
      if (raw == null || raw.isEmpty) {
        return const _MigrationStepResult(count: 0);
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const _MigrationStepResult(
          count: 0,
          error: 'Invalid chat rooms format',
        );
      }

      var count = 0;
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          try {
            final room = ChatRoomModel.fromJson(item);
            await _db.upsertRoom(
              ChatRoomEntry(
                id: room.id,
                name: room.name,
                description: room.description,
                ownerId: room.ownerId,
                isPrivate: room.isPrivate,
                passwordHash: room.passwordHash,
                memberIds: encodeMemberIds(room.memberIds),
                maxMembers: room.maxMembers,
                createdAt: room.createdAt,
                updatedAt: room.updatedAt,
              ),
            );
            await _db.updateSyncMetadata(room.id, 'room');
            count++;
          } catch (_) {
            // Skip invalid entries
          }
        }
      }

      return _MigrationStepResult(count: count);
    } catch (e) {
      return _MigrationStepResult(count: 0, error: 'Chat rooms error: $e');
    }
  }

  Future<void> _cleanupOldData() async {
    // Remove conversation store
    await _prefs.remove(_conversationStoreKey);

    // Remove all message stores
    final allKeys = _prefs.getKeys().toList();
    for (final key in allKeys) {
      if (key.startsWith(_chatMessagesPrefix)) {
        await _prefs.remove(key);
      }
    }

    // Remove chat room store
    await _prefs.remove(_chatRoomStoreKey);

    // Remove chat room sync metadata
    await _prefs.remove('chat_room_sync_metadata_v1');
  }

  /// Force reset migration status (for testing or re-migration).
  Future<void> resetMigrationStatus() async {
    await _prefs.remove(_migrationCompleteKey);
  }
}

class _MigrationStepResult {
  const _MigrationStepResult({required this.count, this.error});

  final int count;
  final String? error;
}

/// Result of the migration process.
class MigrationResult {
  const MigrationResult({
    this.alreadyMigrated = false,
    required this.conversationsMigrated,
    required this.messagesMigrated,
    required this.roomsMigrated,
    this.errors,
  });

  /// Whether migration was already completed before this run.
  final bool alreadyMigrated;

  /// Number of conversations migrated.
  final int conversationsMigrated;

  /// Number of messages migrated.
  final int messagesMigrated;

  /// Number of chat rooms migrated.
  final int roomsMigrated;

  /// Any errors encountered during migration.
  final List<String>? errors;

  /// Whether migration completed without errors.
  bool get success => errors == null || errors!.isEmpty;

  /// Total items migrated.
  int get totalMigrated =>
      conversationsMigrated + messagesMigrated + roomsMigrated;

  @override
  String toString() {
    if (alreadyMigrated) {
      return 'MigrationResult(already migrated)';
    }
    final errorStr = errors != null ? ', errors: $errors' : '';
    return 'MigrationResult('
        'conversations: $conversationsMigrated, '
        'messages: $messagesMigrated, '
        'rooms: $roomsMigrated$errorStr)';
  }
}
