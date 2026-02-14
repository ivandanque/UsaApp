import 'dart:async';
import 'dart:convert';

import '../../../../core/database/app_database.dart';
import 'chat_message_query_service.dart';
import '../models/chat_message_model.dart';
import '../../domain/entities/chat_attachment.dart';

/// Data source for chat messages using drift (SQLite).
///
/// Replaces [PersistentChatMessageDataSource] with SQLite-backed storage
/// that supports efficient pagination and search.
class DriftChatMessageDataSource {
  DriftChatMessageDataSource(this._db, this._queryService);

  final AppDatabase _db;
  final ChatMessageQueryService? _queryService;
  // Cache per-conversation broadcast streams to avoid repeatedly
  // opening/closing Drift query streams which can schedule timers
  // (observed as pending timers in widget tests). Keeping a cached
  // broadcast stream avoids the query being closed when a widget
  // unmounts, removing the timer race in tests.
  final Map<String, Stream<List<ChatMessageModel>>> _cachedMessageStreams = {};

  /// Watch all messages for a conversation.
  Stream<List<ChatMessageModel>> watchMessages(String conversationId) {
    // Delegate to the long-lived query service if available; otherwise
    // fall back to creating an on-demand stream.
    if (_queryService != null) {
      return _queryService.watch(conversationId);
    }
    return _cachedMessageStreams.putIfAbsent(conversationId, () {
      final stream = Stream<List<ChatMessageModel>>.multi((controller) {
        StreamSubscription<List<ChatMessageModel>>? sub;
        sub = _db
            .watchMessages(conversationId)
            .map(
              (entries) => entries.map(_entryToModel).toList(growable: false),
            )
            .listen(
              (data) {
                controller.add(data);
              },
              onError: (Object e, StackTrace? st) {
                controller.addError(e, st);
              },
            );
        controller.onCancel = () async {
          await sub?.cancel();
        };
      }, isBroadcast: true);
      return stream;
    });
  }

  /// Watch messages with pagination (most recent first).
  Stream<List<ChatMessageModel>> watchMessagesPaginated(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) {
    return _db
        .watchMessagesPaginated(conversationId, limit: limit, offset: offset)
        .map((entries) => entries.map(_entryToModel).toList(growable: false));
  }

  /// Get messages before a certain time (for infinite scroll).
  Future<List<ChatMessageModel>> getMessagesBefore(
    String conversationId,
    DateTime before, {
    int limit = 50,
  }) async {
    final entries = await _db.getMessagesBefore(
      conversationId,
      before,
      limit: limit,
    );
    return entries.map(_entryToModel).toList(growable: false);
  }

  /// Save a message.
  Future<void> saveMessage(
    String conversationId,
    ChatMessageModel message,
  ) async {
    await _db.upsertMessage(_modelToEntry(message));
    return;
  }

  // DEBUG helper: return current message count for a conversation

  /// Save multiple messages in batch (for migration/sync).
  Future<void> saveMessagesBatch(List<ChatMessageModel> messages) {
    final entries = messages.map(_modelToEntry).toList(growable: false);
    return _db.insertMessagesBatch(entries);
  }

  /// Clear all messages in a conversation.
  Future<void> clearConversation(String conversationId) {
    return _db.clearConversationMessages(conversationId);
  }

  /// Search messages by content.
  Future<List<ChatMessageModel>> searchMessages(
    String query, {
    String? conversationId,
    int limit = 50,
  }) async {
    final entries = await _db.searchMessages(
      query,
      conversationId: conversationId,
      limit: limit,
    );
    return entries.map(_entryToModel).toList(growable: false);
  }

  /// Get total message count for a conversation.
  Future<int> getMessageCount(String conversationId) {
    return _db.getMessageCount(conversationId);
  }

  /// Check whether a message with the given senderId and sentAt already exists.
  /// Used by history sync to avoid inserting duplicates when IDs differ.
  Future<bool> messageExistsBySenderAt({
    required String conversationId,
    required String senderId,
    required DateTime sentAt,
  }) {
    return _db.messageExistsBySenderAt(
      conversationId: conversationId,
      senderId: senderId,
      sentAt: sentAt,
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONVERTERS
  // ─────────────────────────────────────────────────────────────────────────

  ChatMessageModel _entryToModel(ChatMessageEntry entry) {
    return ChatMessageModel(
      id: entry.id,
      conversationId: entry.conversationId,
      senderId: entry.senderId,
      sender: entry.sender,
      content: entry.content,
      sentAt: entry.sentAt,
      attachments: _decodeAttachments(entry.attachments),
    );
  }

  ChatMessageEntry _modelToEntry(ChatMessageModel model) {
    return ChatMessageEntry(
      id: model.id,
      conversationId: model.conversationId,
      senderId: model.senderId,
      sender: model.sender,
      content: model.content,
      sentAt: model.sentAt,
      attachments: _encodeAttachments(model.attachments),
    );
  }

  List<ChatAttachment> _decodeAttachments(String? raw) {
    if (raw == null || raw.isEmpty) return const <ChatAttachment>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(ChatAttachment.fromJson)
            .toList(growable: false);
      }
    } catch (_) {}
    return const <ChatAttachment>[];
  }

  String _encodeAttachments(List<ChatAttachment> attachments) {
    try {
      return jsonEncode(attachments.map((a) => a.toJson()).toList());
    } catch (_) {
      return '[]';
    }
  }
}
