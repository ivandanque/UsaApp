import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';
import '../utils/logger.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// The main database for the application.
///
/// Uses drift (SQLite) for persistent storage of chat rooms, conversations,
/// and messages with support for reactive queries and efficient pagination.
@DriftDatabase(tables: [ChatRooms, Conversations, ChatMessages, SyncMetadata])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor]) : super(executor ?? _openConnection());

  final Logger _logger = const Logger('AppDatabase');

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration {
    return MigrationStrategy(
      onCreate: (Migrator m) async {
        await m.createAll();
      },
      onUpgrade: (Migrator m, int from, int to) async {
        if (from < 2) {
          await m.addColumn(conversations, conversations.isPrivate);
          await m.addColumn(conversations, conversations.passwordHash);
        }
      },
    );
  }

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'usaapp_chat.db');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CHAT ROOMS
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all chat rooms ordered by last updated.
  Stream<List<ChatRoomEntry>> watchAllRooms() {
    return (select(
      chatRooms,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch();
  }

  /// Get a room by ID.
  Future<ChatRoomEntry?> getRoomById(String id) {
    return (select(chatRooms)..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Insert or update a chat room.
  Future<void> upsertRoom(ChatRoomEntry room) {
    return into(chatRooms).insertOnConflictUpdate(room);
  }

  /// Delete a chat room.
  Future<int> deleteRoom(String id) {
    return (delete(chatRooms)..where((t) => t.id.equals(id))).go();
  }

  /// Get rooms modified since a timestamp.
  Future<List<ChatRoomEntry>> getRoomsModifiedSince(DateTime since) {
    return (select(
      chatRooms,
    )..where((t) => t.updatedAt.isBiggerThanValue(since))).get();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONVERSATIONS
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch all conversations ordered by last updated.
  Stream<List<ConversationEntry>> watchAllConversations() {
    return (select(
      conversations,
    )..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).watch();
  }

  /// Get a conversation by ID.
  Future<ConversationEntry?> getConversationById(String id) {
    return (select(
      conversations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
  }

  /// Insert or update a conversation.
  Future<void> upsertConversation(ConversationEntry conversation) {
    return into(conversations).insertOnConflictUpdate(conversation);
  }

  /// Delete a conversation and its messages.
  Future<void> deleteConversation(String id) async {
    try {
      _logger.info('[AppDatabase] deleteConversation id=$id');
    } catch (_) {}
    await (delete(
      chatMessages,
    )..where((t) => t.conversationId.equals(id))).go();
    await (delete(conversations)..where((t) => t.id.equals(id))).go();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MESSAGES
  // ─────────────────────────────────────────────────────────────────────────

  /// Watch messages for a conversation, ordered by sent time.
  Stream<List<ChatMessageEntry>> watchMessages(String conversationId) {
    return (select(chatMessages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.asc(t.sentAt)]))
        .watch();
  }

  /// Watch messages with pagination (for large conversations).
  Stream<List<ChatMessageEntry>> watchMessagesPaginated(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    return (select(chatMessages)
          ..where((t) => t.conversationId.equals(conversationId))
          ..orderBy([(t) => OrderingTerm.desc(t.sentAt)])
          ..limit(limit, offset: offset))
        .watch();
  }

  /// Get messages before a certain time (for infinite scroll).
  Future<List<ChatMessageEntry>> getMessagesBefore(
    String conversationId,
    DateTime before, {
    int limit = 50,
  }) {
    return (select(chatMessages)
          ..where(
            (t) =>
                t.conversationId.equals(conversationId) &
                t.sentAt.isSmallerThanValue(before),
          )
          ..orderBy([(t) => OrderingTerm.desc(t.sentAt)])
          ..limit(limit))
        .get();
  }

  /// Insert or update a message.
  Future<void> upsertMessage(ChatMessageEntry message) {
    try {
      _logger.info(
        '[AppDatabase] upsertMessage id=${message.id} convo=${message.conversationId} db=$hashCode',
      );
    } catch (_) {}
    return into(chatMessages).insertOnConflictUpdate(message);
  }

  /// Insert multiple messages in a batch (for migration/sync).
  Future<void> insertMessagesBatch(List<ChatMessageEntry> messages) async {
    try {
      _logger.info(
        '[AppDatabase] insertMessagesBatch count=${messages.length}',
      );
    } catch (_) {}
    await batch((batch) {
      batch.insertAllOnConflictUpdate(chatMessages, messages);
    });
  }

  /// Delete all messages in a conversation.
  Future<int> clearConversationMessages(String conversationId) {
    try {
      _logger.info(
        '[AppDatabase] clearConversationMessages convo=$conversationId',
      );
    } catch (_) {}
    return (delete(
      chatMessages,
    )..where((t) => t.conversationId.equals(conversationId))).go();
  }

  /// Search messages by content.
  ///
  /// Uses drift's [contains] which wraps the query in `%..%` but
  /// parameterises the value, preventing LIKE wildcard injection.
  Future<List<ChatMessageEntry>> searchMessages(
    String query, {
    String? conversationId,
    int limit = 50,
  }) {
    final q = select(chatMessages)
      ..where((t) => t.content.contains(query))
      ..orderBy([(t) => OrderingTerm.desc(t.sentAt)])
      ..limit(limit);

    if (conversationId != null) {
      q.where((t) => t.conversationId.equals(conversationId));
    }

    return q.get();
  }

  /// Get message count for a conversation.
  Future<int> getMessageCount(String conversationId) async {
    final countExp = chatMessages.id.count();
    final query = selectOnly(chatMessages)
      ..addColumns([countExp])
      ..where(chatMessages.conversationId.equals(conversationId));
    final result = await query.getSingle();
    return result.read(countExp) ?? 0;
  }

  /// Check whether a message with the given senderId and sentAt already exists
  /// in the conversation. Used for deduplication when message IDs differ
  /// between sender and host.
  Future<bool> messageExistsBySenderAt({
    required String conversationId,
    required String senderId,
    required DateTime sentAt,
  }) async {
    final query = select(chatMessages)
      ..where(
        (t) =>
            t.conversationId.equals(conversationId) &
            t.senderId.equals(senderId) &
            t.sentAt.equals(sentAt),
      )
      ..limit(1);
    final result = await query.getSingleOrNull();
    return result != null;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SYNC METADATA
  // ─────────────────────────────────────────────────────────────────────────

  /// Update sync metadata for an entity.
  Future<void> updateSyncMetadata(String entityId, String entityType) async {
    final existing =
        await (select(syncMetadata)..where(
              (t) =>
                  t.entityId.equals(entityId) & t.entityType.equals(entityType),
            ))
            .getSingleOrNull();

    final entry = SyncMetadataEntry(
      entityId: entityId,
      entityType: entityType,
      lastModified: DateTime.now().toUtc(),
      version: (existing?.version ?? 0) + 1,
    );

    await into(syncMetadata).insertOnConflictUpdate(entry);
  }

  /// Get all sync metadata.
  Future<List<SyncMetadataEntry>> getAllSyncMetadata() {
    return select(syncMetadata).get();
  }

  /// Get sync metadata for a specific entity type.
  Future<List<SyncMetadataEntry>> getSyncMetadataByType(String entityType) {
    return (select(
      syncMetadata,
    )..where((t) => t.entityType.equals(entityType))).get();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UTILITIES
  // ─────────────────────────────────────────────────────────────────────────

  /// Clear all data (for testing or reset).
  Future<void> clearAll() async {
    await delete(chatMessages).go();
    await delete(conversations).go();
    await delete(chatRooms).go();
    await delete(syncMetadata).go();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPER EXTENSIONS
// ─────────────────────────────────────────────────────────────────────────────

/// Extension to convert member IDs between List and JSON string.
extension MemberIdsHelper on ChatRoomEntry {
  List<String> get memberIdsList {
    try {
      final decoded = jsonDecode(memberIds);
      if (decoded is List) {
        return List<String>.from(decoded.map((e) => e.toString()));
      }
    } catch (_) {}
    return [];
  }
}

/// Helper to encode member IDs list to JSON string.
String encodeMemberIds(List<String> ids) => jsonEncode(ids);
