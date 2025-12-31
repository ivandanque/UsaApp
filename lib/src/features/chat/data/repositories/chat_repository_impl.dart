import 'dart:async';

import '../../domain/entities/chat_message.dart';
import '../../domain/repositories/chat_repository.dart';
import '../datasources/drift_chat_message_data_source.dart';
import '../models/chat_message_model.dart';

class ChatRepositoryImpl implements ChatRepository {
  ChatRepositoryImpl(this._messageDataSource);

  final DriftChatMessageDataSource _messageDataSource;

  @override
  Future<void> sendMessage(String conversationId, ChatMessage message) {
    final model = ChatMessageModel.fromEntity(message);
    return _messageDataSource.saveMessage(conversationId, model);
  }

  @override
  Stream<List<ChatMessage>> watchMessages(String conversationId) {
    return _messageDataSource
        .watchMessages(conversationId)
        .map(
          (models) =>
              models.map((model) => model.toEntity()).toList(growable: false),
        );
  }

  @override
  Future<void> clearConversation(String conversationId) {
    return _messageDataSource.clearConversation(conversationId);
  }
}
