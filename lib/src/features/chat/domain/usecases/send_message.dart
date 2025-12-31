import '../../../../core/usecase/use_case.dart';
import '../entities/chat_message.dart';
import '../entities/chat_attachment.dart';
import '../repositories/chat_repository.dart';

class SendMessage extends UseCase<ChatMessage, SendMessageParams> {
  SendMessage(this._repository);

  final ChatRepository _repository;

  @override
  Future<ChatMessage> call(SendMessageParams params) async {
    // Ensure the analyzer sees a concrete `SendMessageParams` type here
    // (some analyzer configurations may treat generic params as `dynamic`).
    final SendMessageParams p = params;
    final id = params.id ?? _generateId();
    final sentAt = p.sentAt ?? DateTime.now();
    // Validate attachments size for inline attachments unless they're
    // external (served via transport). External attachments are shared via
    // the P2P transport and only referenced in the message metadata.
    const maxAttachmentSizeBytes = 256 * 1024; // 256 KB
    if (!p.attachmentsAreExternal) {
      for (final a in p.attachments ?? const <ChatAttachment>[]) {
        if (a.sizeBytes > maxAttachmentSizeBytes) {
          throw ArgumentError(
            'Attachment "${a.filename}" exceeds maximum allowed size of $maxAttachmentSizeBytes bytes',
          );
        }
      }
    }

    final message = ChatMessage(
      id: id,
      conversationId: p.conversationId,
      senderId: p.senderId,
      sender: p.sender,
      content: p.content,
      sentAt: sentAt,
      attachments: p.attachments ?? const <ChatAttachment>[],
    );

    await _repository.sendMessage(p.conversationId, message);
    return message;
  }

  String _generateId() => DateTime.now().microsecondsSinceEpoch.toString();
}

class SendMessageParams {
  const SendMessageParams({
    this.id,
    required this.conversationId,
    required this.senderId,
    required this.sender,
    required this.content,
    this.sentAt,
    this.attachments,
    this.attachmentsAreExternal = false,
  });

  final String? id;
  final String conversationId;
  final String senderId;
  final String sender;
  final String content;
  final DateTime? sentAt;
  final List<ChatAttachment>? attachments;
  final bool attachmentsAreExternal;
}
