import 'dart:async';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/read_receipt.dart';

/// Data source for message read receipts using drift (SQLite).
///
/// Provides CRUD operations and reactive streams for read receipt data,
/// enabling Messenger-style "seen by" indicators in the chat UI.
class DriftReadReceiptDataSource {
  DriftReadReceiptDataSource(this._db);

  final AppDatabase _db;

  /// Save (upsert) a read receipt. If the same user has already seen
  /// the same message, the record is updated with the latest timestamp.
  Future<void> saveReadReceipt(ReadReceipt receipt) async {
    await _db.upsertReadReceipt(_toEntry(receipt));
  }

  /// Watch all read receipts for a conversation reactively.
  /// Returns a map of messageId → list of read receipts for that message.
  Stream<Map<String, List<ReadReceipt>>> watchReadReceipts(
    String conversationId,
  ) {
    return _db.watchReadReceipts(conversationId).map((entries) {
      final map = <String, List<ReadReceipt>>{};
      for (final entry in entries) {
        final receipt = _toEntity(entry);
        map.putIfAbsent(receipt.messageId, () => <ReadReceipt>[]).add(receipt);
      }
      return map;
    });
  }

  /// Get read receipts for a specific message (non-reactive).
  Future<List<ReadReceipt>> getReadReceiptsForMessage(String messageId) async {
    final entries = await _db.getReadReceiptsForMessage(messageId);
    return entries.map(_toEntity).toList(growable: false);
  }

  /// Clear all read receipts for a conversation.
  Future<void> clearReadReceipts(String conversationId) {
    return _db.clearReadReceipts(conversationId);
  }

  /// Get all read receipts for a conversation (non-reactive, for sync).
  Future<List<ReadReceipt>> getAllReadReceipts(String conversationId) async {
    final entries = await _db.getAllReadReceipts(conversationId);
    return entries.map(_toEntity).toList(growable: false);
  }

  // ── CONVERTERS ──

  MessageReadReceiptEntry _toEntry(ReadReceipt receipt) {
    return MessageReadReceiptEntry(
      messageId: receipt.messageId,
      conversationId: receipt.conversationId,
      seenByUserId: receipt.seenByUserId,
      seenByDisplayName: receipt.seenByDisplayName,
      seenByProfileImage: receipt.seenByProfileImage,
      seenAt: receipt.seenAt,
    );
  }

  ReadReceipt _toEntity(MessageReadReceiptEntry entry) {
    return ReadReceipt(
      messageId: entry.messageId,
      conversationId: entry.conversationId,
      seenByUserId: entry.seenByUserId,
      seenByDisplayName: entry.seenByDisplayName,
      seenByProfileImage: entry.seenByProfileImage,
      seenAt: entry.seenAt,
    );
  }
}
