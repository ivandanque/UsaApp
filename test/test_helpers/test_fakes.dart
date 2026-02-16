import 'dart:async';

// removed unused imports
import 'package:usaapp/src/features/chat/domain/entities/chat_message_payload.dart';
import 'package:usaapp/src/features/chat/domain/entities/conversation.dart';
import 'package:usaapp/src/features/p2p/data/services/p2p_service.dart';
import 'package:usaapp/src/features/p2p/presentation/controllers/p2p_session_controller.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usaapp/src/core/services/notification_service.dart';

/// Lightweight fake P2P controller used by widget tests to avoid invoking
/// platform plugins or starting real services.
class FakeP2pSessionController extends P2pSessionController {
  final StreamController<ChatMessagePayload> _incoming =
      StreamController<ChatMessagePayload>.broadcast();

  FakeP2pSessionController()
    : super(
        p2pService: P2pService(),
        conversationStore: null,
        latencyProbeService: null,
        notificationService: NotificationService(
          plugin: FlutterLocalNotificationsPlugin(),
        ),
        backgroundScanningEnabled: () => false,
        scanCadenceSeconds: () => 5,
      );

  @override
  Stream<ChatMessagePayload> get incomingMessages => _incoming.stream;

  @override
  void setActiveConversation(
    Conversation conversation, {
    bool isPrivate = false,
    String? passwordHash,
    bool requiresApproval = false,
  }) {
    // Keep behavior minimal for tests but still record active convo via base impl.
    super.setActiveConversation(
      conversation,
      isPrivate: isPrivate,
      passwordHash: passwordHash,
      requiresApproval: requiresApproval,
    );
  }

  void addIncoming(ChatMessagePayload payload) {
    if (!_incoming.isClosed) _incoming.add(payload);
  }

  @override
  void dispose() {
    try {
      _incoming.close();
    } catch (_) {}
    super.dispose();
  }
}

/// Simple in-memory fake conversation store for tests. Not a full replacement
/// for the production drift-backed store, but sufficient for widget tests.
class FakeConversationStore {
  final Map<String, Conversation> _store = {};

  String _generateId() {
    const alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final random = DateTime.now().microsecondsSinceEpoch;
    final buffer = StringBuffer();
    for (var i = 0; i < 12; i++) {
      buffer.write(alphabet[(random + i) % alphabet.length]);
    }
    return buffer.toString();
  }

  Future<Conversation> createConversation(
    String title, {
    bool isPrivate = false,
    String? passwordHash,
  }) async {
    final id = _generateId();
    final now = DateTime.now().toUtc();
    final conv = Conversation(
      id: id,
      title: title.trim().isEmpty ? 'Conversation' : title.trim(),
      isPrivate: isPrivate,
      passwordHash: passwordHash,
      createdAt: now,
      updatedAt: now,
    );
    _store[id] = conv;
    return conv;
  }

  Future<Conversation> ensureConversationExists({
    required String id,
    required String title,
    bool? isPrivate,
    String? passwordHash,
  }) async {
    final existing = _store[id];
    final now = DateTime.now().toUtc();
    if (existing != null) {
      final needsUpdate =
          (title.trim().isNotEmpty && existing.title != title.trim()) ||
          (isPrivate != null && existing.isPrivate != isPrivate) ||
          (passwordHash != null && existing.passwordHash != passwordHash);
      if (needsUpdate) {
        final updated = Conversation(
          id: existing.id,
          title: title.trim().isNotEmpty ? title.trim() : existing.title,
          isPrivate: isPrivate ?? existing.isPrivate,
          passwordHash: passwordHash ?? existing.passwordHash,
          createdAt: existing.createdAt,
          updatedAt: now,
        );
        _store[id] = updated;
        return updated;
      }
      return existing;
    }
    final newConversation = Conversation(
      id: id,
      title: title.trim().isEmpty ? 'Conversation' : title.trim(),
      isPrivate: isPrivate ?? false,
      passwordHash: passwordHash,
      createdAt: now,
      updatedAt: now,
    );
    _store[id] = newConversation;
    return newConversation;
  }

  Future<void> deleteConversation(String id) async {
    _store.remove(id);
  }
}
