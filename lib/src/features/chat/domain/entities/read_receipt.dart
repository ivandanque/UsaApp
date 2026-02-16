/// Represents a read receipt — evidence that a specific user has seen
/// a specific message in a conversation.
class ReadReceipt {
  const ReadReceipt({
    required this.messageId,
    required this.conversationId,
    required this.seenByUserId,
    required this.seenByDisplayName,
    this.seenByProfileImage,
    required this.seenAt,
  });

  /// The ID of the message that was seen.
  final String messageId;

  /// The conversation the message belongs to.
  final String conversationId;

  /// The peer ID of the user who read the message.
  final String seenByUserId;

  /// Display name of the user who read the message.
  final String seenByDisplayName;

  /// Optional base64-encoded profile image of the reader.
  final String? seenByProfileImage;

  /// When the message was seen (UTC).
  final DateTime seenAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'messageId': messageId,
    'conversationId': conversationId,
    'seenByUserId': seenByUserId,
    'seenByDisplayName': seenByDisplayName,
    if (seenByProfileImage != null) 'seenByProfileImage': seenByProfileImage,
    'seenAt': seenAt.toUtc().toIso8601String(),
    'seenAtMs': seenAt.toUtc().millisecondsSinceEpoch,
  };

  factory ReadReceipt.fromJson(Map<String, dynamic> json) {
    // Parse seenAt with epoch-ms fallback (same pattern as ChatMessageModel).
    final seenAtRaw = json['seenAt'];
    final seenAtMsRaw = json['seenAtMs'];
    DateTime parsedSeenAt;
    if (seenAtRaw is String) {
      final primary = DateTime.tryParse(seenAtRaw)?.toUtc();
      if (primary != null) {
        parsedSeenAt = primary;
      } else if (seenAtMsRaw is num) {
        parsedSeenAt = DateTime.fromMillisecondsSinceEpoch(
          seenAtMsRaw.toInt(),
          isUtc: true,
        );
      } else {
        parsedSeenAt = DateTime.now().toUtc();
      }
    } else if (seenAtMsRaw is num) {
      parsedSeenAt = DateTime.fromMillisecondsSinceEpoch(
        seenAtMsRaw.toInt(),
        isUtc: true,
      );
    } else {
      parsedSeenAt = DateTime.now().toUtc();
    }

    return ReadReceipt(
      messageId: json['messageId'] as String,
      conversationId: json['conversationId'] as String,
      seenByUserId: json['seenByUserId'] as String,
      seenByDisplayName: json['seenByDisplayName'] as String,
      seenByProfileImage: json['seenByProfileImage'] as String?,
      seenAt: parsedSeenAt,
    );
  }

  ReadReceipt copyWith({
    String? messageId,
    String? conversationId,
    String? seenByUserId,
    String? seenByDisplayName,
    String? seenByProfileImage,
    DateTime? seenAt,
  }) {
    return ReadReceipt(
      messageId: messageId ?? this.messageId,
      conversationId: conversationId ?? this.conversationId,
      seenByUserId: seenByUserId ?? this.seenByUserId,
      seenByDisplayName: seenByDisplayName ?? this.seenByDisplayName,
      seenByProfileImage: seenByProfileImage ?? this.seenByProfileImage,
      seenAt: seenAt ?? this.seenAt,
    );
  }
}
