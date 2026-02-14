import 'dart:async';

import '../../../../core/database/app_database.dart';
import '../../../../core/utils/logger.dart';
import '../models/chat_message_model.dart';

/// Long-lived service that owns Drift query subscriptions for chat messages.
///
/// Keeps a single DB subscription per conversation and exposes a broadcast
/// stream for controllers/widgets to listen to. This prevents opening/closing
/// the underlying Drift query repeatedly which can schedule timers and
/// cause races in the test harness.
class ChatMessageQueryService {
  ChatMessageQueryService(this._db);

  final AppDatabase _db;

  final Map<String, Stream<List<ChatMessageModel>>> _streams = {};
  final Map<String, StreamController<List<ChatMessageModel>>> _controllers = {};
  final Map<String, List<ChatMessageModel>> _lastEmitted = {};

  Stream<List<ChatMessageModel>> watch(String conversationId) {
    // Check if we have a cached stream but its controller is closed (race with
    // onCancel). If so, remove it so we create a fresh one below.
    final existing = _controllers[conversationId];
    if (existing != null && existing.isClosed) {
      _controllers.remove(conversationId);
      _streams.remove(conversationId);
      _lastEmitted.remove(conversationId);
    }

    return _streams.putIfAbsent(conversationId, () {
      // DEBUG: log which DB instance is used for this watch
      const tag = 'ChatMessageQueryService';
      final logger = const Logger(tag);
      logger.info(
        '[ChatMessageQueryService] watch convo=$conversationId db=${_db.hashCode}',
      );
      final controller = StreamController<List<ChatMessageModel>>.broadcast();
      StreamSubscription<List<ChatMessageModel>>? sub;

      controller.onListen = () {
        if (sub != null) {
          // Already subscribed — replay last known snapshot for new listener
          final previously = _lastEmitted[conversationId];
          if (previously != null && !controller.isClosed) {
            controller.add(previously);
          }
          return;
        }

        // Replay cached snapshot immediately so new listeners don't wait
        final previously = _lastEmitted[conversationId];
        if (previously != null && !controller.isClosed) {
          controller.add(previously);
        }

        sub = _db
            .watchMessages(conversationId)
            .map(
              (entries) => entries
                  .map((e) => ChatMessageModel.fromEntry(e))
                  .toList(growable: false),
            )
            .listen(
              (data) {
                try {
                  final ids = data.map((m) => m.id).join(',');
                  logger.info(
                    '[ChatMessageQueryService] convo=$conversationId got ${data.length} messages ids=[$ids]',
                  );
                } catch (_) {}
                // Cache latest snapshot for immediate replay to future listeners
                _lastEmitted[conversationId] = data;
                if (!controller.isClosed) controller.add(data);
              },
              onError: (Object e, StackTrace? st) {
                if (!controller.isClosed) controller.addError(e, st);
              },
            );
      };

      // When controller has no listeners, cancel DB subscription and remove cache
      controller.onCancel = () async {
        logger.info(
          '[ChatMessageQueryService] controller.onCancel convo=$conversationId',
        );
        await sub?.cancel();
        sub = null;
        // small delay to allow any pending stream-work to settle before closing
        await Future<void>.delayed(Duration.zero);
        if (!controller.hasListener) {
          logger.info(
            '[ChatMessageQueryService] removing cache for convo=$conversationId',
          );
          _controllers.remove(conversationId);
          _streams.remove(conversationId);
          // Keep _lastEmitted so history page can replay instantly
          await controller.close();
        }
      };

      _controllers[conversationId] = controller;
      return controller.stream;
    });
  }

  /// Close all controllers and subscriptions. Used when shutting down the app.
  Future<void> dispose() async {
    for (final c in _controllers.values) {
      try {
        await c.close();
      } catch (_) {}
    }
    _controllers.clear();
    _streams.clear();
  }
}
