import 'package:flutter/foundation.dart';

import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_attachment.dart';
import '../../../../core/database/app_database.dart';
import 'dart:convert';

class ChatMessageModel extends ChatMessage {
  const ChatMessageModel({
    required super.id,
    required super.conversationId,
    required super.senderId,
    required super.sender,
    required super.content,
    required super.sentAt,
    super.attachments = const [],
  });

  factory ChatMessageModel.fromEntity(ChatMessage entity) {
    return ChatMessageModel(
      id: entity.id,
      conversationId: entity.conversationId,
      senderId: entity.senderId,
      sender: entity.sender,
      content: entity.content,
      sentAt: entity.sentAt,
      attachments: entity.attachments.toList(growable: false),
    );
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final sentAtRaw = json['sentAt'];
    final sentAtMsRaw = json['sentAtMs'];
    final attachmentsRaw = json['attachments'];

    // Parse sentinel timestamp with epoch-ms fallback to survive
    // transmission corruption during P2P history sync.
    DateTime parsedSentAt;
    if (sentAtRaw is String) {
      final primary = DateTime.tryParse(sentAtRaw)?.toUtc();
      if (primary != null) {
        parsedSentAt = primary;
      } else {
        debugPrint(
          'ChatMessageModel.fromJson: DateTime.tryParse failed for '
          'sentAt="$sentAtRaw" (msg ${json['id']}). '
          'Trying sentAtMs fallback.',
        );
        if (sentAtMsRaw is num) {
          parsedSentAt = DateTime.fromMillisecondsSinceEpoch(
            sentAtMsRaw.toInt(),
            isUtc: true,
          );
        } else {
          debugPrint(
            'ChatMessageModel.fromJson: No sentAtMs fallback for '
            'msg ${json['id']}. Using DateTime.now() as last resort.',
          );
          parsedSentAt = DateTime.now().toUtc();
        }
      }
    } else if (sentAtMsRaw is num) {
      parsedSentAt = DateTime.fromMillisecondsSinceEpoch(
        sentAtMsRaw.toInt(),
        isUtc: true,
      );
    } else {
      parsedSentAt = DateTime.now().toUtc();
    }

    return ChatMessageModel(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      sender: json['sender'] as String,
      content: json['content'] as String,
      sentAt: parsedSentAt,
      attachments: attachmentsRaw is List
          ? attachmentsRaw
                .whereType<Map<String, dynamic>>()
                .map(ChatAttachment.fromJson)
                .toList(growable: false)
          : const [],
    );
  }

  ChatMessage toEntity() {
    return ChatMessage(
      id: id,
      conversationId: conversationId,
      senderId: senderId,
      sender: sender,
      content: content,
      sentAt: sentAt,
      attachments: attachments,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'conversationId': conversationId,
      'senderId': senderId,
      'sender': sender,
      'content': content,
      'sentAt': sentAt.toUtc().toIso8601String(),
      'sentAtMs': sentAt.toUtc().millisecondsSinceEpoch,
      'attachments': attachments.map((a) => a.toJson()).toList(),
    };
  }

  factory ChatMessageModel.fromEntry(ChatMessageEntry entry) {
    // ChatMessageEntry.attachments is a String (JSON) in the DB schema
    List<ChatAttachment> attachments = const [];
    try {
      final raw = entry.attachments;
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          attachments = decoded
              .whereType<Map<String, dynamic>>()
              .map(ChatAttachment.fromJson)
              .toList(growable: false);
        }
      }
    } catch (_) {
      attachments = const [];
    }

    return ChatMessageModel(
      id: entry.id,
      conversationId: entry.conversationId,
      senderId: entry.senderId,
      sender: entry.sender,
      content: entry.content,
      sentAt: entry.sentAt,
      attachments: attachments,
    );
  }
}
