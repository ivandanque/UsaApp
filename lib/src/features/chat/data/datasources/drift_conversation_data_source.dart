import 'dart:async';
import 'dart:math';

import '../../../../core/database/app_database.dart';
import '../../domain/entities/conversation.dart';

/// Data source for conversations using drift (SQLite).
///
/// Replaces [ConversationStore] with SQLite-backed storage.
class DriftConversationDataSource {
  DriftConversationDataSource(this._db);

  final AppDatabase _db;

  /// Watch all conversations ordered by last updated.
  Stream<List<Conversation>> watchAll() {
    return _db.watchAllConversations().map(
      (entries) => entries.map(_entryToConversation).toList(growable: false),
    );
  }

  /// Get a conversation by ID.
  Future<Conversation?> getConversationById(String id) async {
    final entry = await _db.getConversationById(id);
    return entry != null ? _entryToConversation(entry) : null;
  }

  /// Save a conversation.
  Future<void> saveConversation(Conversation conversation) {
    return _db.upsertConversation(_conversationToEntry(conversation));
  }

  /// Save multiple conversations in batch (for migration).
  Future<void> saveConversationsBatch(List<Conversation> conversations) async {
    for (final conv in conversations) {
      await _db.upsertConversation(_conversationToEntry(conv));
    }
  }

  /// Delete a conversation and its messages.
  Future<void> deleteConversation(String id) {
    return _db.deleteConversation(id);
  }

  /// Ensure a conversation exists, creating if needed.
  Future<Conversation> ensureConversationExists({
    required String id,
    required String title,
    bool? isPrivate,
    String? passwordHash,
  }) async {
    final existing = await _db.getConversationById(id);
    final now = DateTime.now().toUtc();

    if (existing != null) {
      final needsTitleUpdate =
          title.trim().isNotEmpty && existing.title != title.trim();
      final needsPrivacyUpdate =
          (isPrivate != null && existing.isPrivate != isPrivate) ||
          (passwordHash != null && existing.passwordHash != passwordHash);

      if (needsTitleUpdate || needsPrivacyUpdate) {
        final updated = Conversation(
          id: existing.id,
          title: needsTitleUpdate ? title.trim() : existing.title,
          isPrivate: isPrivate ?? existing.isPrivate,
          passwordHash: passwordHash ?? existing.passwordHash,
          createdAt: existing.createdAt,
          updatedAt: now,
        );
        await _db.upsertConversation(_conversationToEntry(updated));
        return updated;
      }
      return _entryToConversation(existing);
    }

    final newConversation = Conversation(
      id: id,
      title: title.trim().isEmpty ? 'Conversation' : title.trim(),
      isPrivate: isPrivate ?? false,
      passwordHash: passwordHash,
      createdAt: now,
      updatedAt: now,
    );
    await _db.upsertConversation(_conversationToEntry(newConversation));
    return newConversation;
  }

  /// Create a new conversation with a generated id.
  Future<Conversation> createConversation(
    String title, {
    bool isPrivate = false,
    String? passwordHash,
  }) async {
    final id = _generateId();
    final now = DateTime.now().toUtc();
    final conversation = Conversation(
      id: id,
      title: title.trim().isEmpty ? 'Conversation' : title.trim(),
      isPrivate: isPrivate,
      passwordHash: passwordHash,
      createdAt: now,
      updatedAt: now,
    );
    await _db.upsertConversation(_conversationToEntry(conversation));
    return conversation;
  }

  /// Update the conversation's updatedAt timestamp (touch).
  Future<void> touchConversation(String id) async {
    final existing = await _db.getConversationById(id);
    if (existing == null) return;
    final updated = Conversation(
      id: existing.id,
      title: existing.title,
      isPrivate: existing.isPrivate,
      passwordHash: existing.passwordHash,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.upsertConversation(_conversationToEntry(updated));
  }

  /// Rename a conversation (update title and updatedAt).
  Future<void> renameConversation({
    required String id,
    required String newTitle,
  }) async {
    final existing = await _db.getConversationById(id);
    if (existing == null) return;
    final updated = Conversation(
      id: existing.id,
      title: newTitle.trim().isEmpty ? existing.title : newTitle.trim(),
      isPrivate: existing.isPrivate,
      passwordHash: existing.passwordHash,
      createdAt: existing.createdAt,
      updatedAt: DateTime.now().toUtc(),
    );
    await _db.upsertConversation(_conversationToEntry(updated));
  }

  String _generateId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = Random.secure();
    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buffer.write(alphabet[random.nextInt(alphabet.length)]);
    }
    return buffer.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CONVERTERS
  // ─────────────────────────────────────────────────────────────────────────

  Conversation _entryToConversation(ConversationEntry entry) {
    return Conversation(
      id: entry.id,
      title: entry.title,
      isPrivate: entry.isPrivate,
      passwordHash: entry.passwordHash,
      createdAt: entry.createdAt,
      updatedAt: entry.updatedAt,
    );
  }

  ConversationEntry _conversationToEntry(Conversation conversation) {
    return ConversationEntry(
      id: conversation.id,
      title: conversation.title,
      isPrivate: conversation.isPrivate,
      passwordHash: conversation.passwordHash,
      createdAt: conversation.createdAt,
      updatedAt: conversation.updatedAt,
    );
  }
}
