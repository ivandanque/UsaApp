import 'chat_attachment.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.sender,
    required this.content,
    required this.sentAt,
    this.attachments = const [],
  });

  final String id;
  final String conversationId;
  final String senderId;
  final String sender;
  final String content;
  final DateTime sentAt;
  final List<ChatAttachment> attachments;

  ChatMessage copyWith({
    String? id,
    String? conversationId,
    String? senderId,
    String? sender,
    String? content,
    DateTime? sentAt,
    List<ChatAttachment>? attachments,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      senderId: senderId ?? this.senderId,
      sender: sender ?? this.sender,
      content: content ?? this.content,
      sentAt: sentAt ?? this.sentAt,
      attachments: attachments ?? this.attachments,
    );
  }
}
