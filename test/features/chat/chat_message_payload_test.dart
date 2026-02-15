import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/core/models/peer_identity.dart';
import 'package:usaapp/src/features/chat/domain/entities/chat_message.dart';
import 'package:usaapp/src/features/chat/domain/entities/chat_message_payload.dart';

void main() {
  group('ChatMessagePayload', () {
    final testDateTime = DateTime.utc(2025, 12, 19, 10, 30, 0);

    group('constructor', () {
      test('creates payload with required fields', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test Conversation',
          senderId: 'user-1',
          senderName: 'Test User',
          content: 'Hello',
          sentAt: testDateTime,
        );

        expect(payload.id, equals('msg-1'));
        expect(payload.conversationId, equals('conv-1'));
        expect(payload.conversationTitle, equals('Test Conversation'));
        expect(payload.senderId, equals('user-1'));
        expect(payload.senderName, equals('Test User'));
        expect(payload.content, equals('Hello'));
        expect(payload.sentAt, equals(testDateTime));
      });

      test('creates payload with profile fields', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Display Name',
          content: 'Hello',
          sentAt: testDateTime,
          senderFullName: 'Full Name',
          senderRole: 'student',
          senderGroupName: 'Group A',
          senderProfileImageBase64: 'base64data',
        );

        expect(payload.senderFullName, equals('Full Name'));
        expect(payload.senderRole, equals('student'));
        expect(payload.senderGroupName, equals('Group A'));
        expect(payload.senderProfileImageBase64, equals('base64data'));
      });

      test('profile fields default to null', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test',
          content: 'Hello',
          sentAt: testDateTime,
        );

        expect(payload.senderFullName, isNull);
        expect(payload.senderRole, isNull);
        expect(payload.senderGroupName, isNull);
        expect(payload.senderProfileImageBase64, isNull);
      });
    });

    group('fromChatMessage', () {
      test('creates payload from chat message', () {
        final chatMessage = ChatMessage(
          id: 'msg-1',
          conversationId: 'conv-1',
          senderId: 'user-1',
          sender: 'Test User',
          content: 'Hello',
          sentAt: testDateTime,
        );

        final payload = ChatMessagePayload.fromChatMessage(
          chatMessage,
          conversationTitle: 'Test Conversation',
        );

        expect(payload.id, equals('msg-1'));
        expect(payload.conversationId, equals('conv-1'));
        expect(payload.conversationTitle, equals('Test Conversation'));
        expect(payload.senderId, equals('user-1'));
        expect(payload.senderName, equals('Test User'));
        expect(payload.content, equals('Hello'));
      });

      test('includes sender identity when provided', () {
        final chatMessage = ChatMessage(
          id: 'msg-1',
          conversationId: 'conv-1',
          senderId: 'user-1',
          sender: 'Display Name',
          content: 'Hello',
          sentAt: testDateTime,
        );

        const identity = PeerIdentity(
          id: 'user-1',
          displayName: 'Display Name',
          name: 'Full Name',
          profileImage: 'base64image',
          groupName: 'Group A',
          role: UserRole.teacher,
        );

        final payload = ChatMessagePayload.fromChatMessage(
          chatMessage,
          conversationTitle: 'Test',
          senderIdentity: identity,
        );

        expect(payload.senderFullName, equals('Full Name'));
        expect(payload.senderRole, equals('teacher'));
        expect(payload.senderGroupName, equals('Group A'));
        expect(payload.senderProfileImageBase64, equals('base64image'));
      });
    });

    group('toChatMessage', () {
      test('converts payload to chat message', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test User',
          content: 'Hello',
          sentAt: testDateTime,
        );

        final message = payload.toChatMessage();

        expect(message.id, equals('msg-1'));
        expect(message.conversationId, equals('conv-1'));
        expect(message.senderId, equals('user-1'));
        expect(message.sender, equals('Test User'));
        expect(message.content, equals('Hello'));
        expect(message.sentAt, equals(testDateTime));
      });
    });

    group('getSenderIdentity', () {
      test('extracts peer identity from payload', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Display Name',
          content: 'Hello',
          sentAt: testDateTime,
          senderFullName: 'Full Name',
          senderRole: 'student',
          senderGroupName: 'Group A',
          senderProfileImageBase64: 'base64data',
        );

        final identity = payload.getSenderIdentity();

        expect(identity.id, equals('user-1'));
        expect(identity.displayName, equals('Display Name'));
        expect(identity.name, equals('Full Name'));
        expect(identity.role, equals(UserRole.student));
        expect(identity.groupName, equals('Group A'));
        expect(identity.profileImage, equals('base64data'));
      });

      test('defaults role to other when not specified', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test',
          content: 'Hello',
          sentAt: testDateTime,
        );

        final identity = payload.getSenderIdentity();

        expect(identity.role, equals(UserRole.other));
      });

      test('handles unknown role value gracefully', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test',
          content: 'Hello',
          sentAt: testDateTime,
          senderRole: 'unknown_role',
        );

        final identity = payload.getSenderIdentity();

        expect(identity.role, equals(UserRole.other));
      });
    });

    group('toJson', () {
      test('serializes required fields', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test Conversation',
          senderId: 'user-1',
          senderName: 'Test User',
          content: 'Hello',
          sentAt: testDateTime,
        );

        final json = payload.toJson();

        expect(json['v'], equals(2));
        expect(json['id'], equals('msg-1'));
        expect(json['conversationId'], equals('conv-1'));
        expect(json['conversationTitle'], equals('Test Conversation'));
        expect(json['senderId'], equals('user-1'));
        expect(json['senderName'], equals('Test User'));
        expect(json['content'], equals('Hello'));
        expect(json['sentAt'], equals('2025-12-19T10:30:00.000Z'));
      });

      test('includes profile fields when present', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test',
          content: 'Hello',
          sentAt: testDateTime,
          senderFullName: 'Full Name',
          senderRole: 'student',
          senderGroupName: 'Group A',
          senderProfileImageBase64: 'base64data',
        );

        final json = payload.toJson();

        expect(json['senderFullName'], equals('Full Name'));
        expect(json['senderRole'], equals('student'));
        expect(json['senderGroupName'], equals('Group A'));
        expect(json['senderProfileImageBase64'], equals('base64data'));
      });

      test('excludes null profile fields', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test',
          content: 'Hello',
          sentAt: testDateTime,
        );

        final json = payload.toJson();

        expect(json.containsKey('senderFullName'), isFalse);
        expect(json.containsKey('senderRole'), isFalse);
        expect(json.containsKey('senderGroupName'), isFalse);
        expect(json.containsKey('senderProfileImageBase64'), isFalse);
      });
    });

    group('encode', () {
      test('returns valid json string', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test',
          content: 'Hello',
          sentAt: testDateTime,
        );

        final encoded = payload.encode();
        final decoded = jsonDecode(encoded) as Map<String, dynamic>;

        expect(decoded, isA<Map<String, dynamic>>());
        expect(decoded['id'], equals('msg-1'));
      });
    });

    group('tryParse', () {
      test('parses valid v2 payload', () {
        final json = jsonEncode({
          'v': 2,
          'id': 'msg-1',
          'conversationId': 'conv-1',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test User',
          'content': 'Hello',
          'sentAt': '2025-12-19T10:30:00.000Z',
          'senderFullName': 'Full Name',
          'senderRole': 'student',
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload, isNotNull);
        expect(payload!.id, equals('msg-1'));
        expect(payload.senderFullName, equals('Full Name'));
        expect(payload.senderRole, equals('student'));
      });

      test('parses valid v1 payload for backward compatibility', () {
        final json = jsonEncode({
          'v': 1,
          'id': 'msg-1',
          'conversationId': 'conv-1',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test User',
          'content': 'Hello',
          'sentAt': '2025-12-19T10:30:00.000Z',
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload, isNotNull);
        expect(payload!.id, equals('msg-1'));
      });

      test('returns null for invalid version', () {
        final json = jsonEncode({
          'v': 99,
          'id': 'msg-1',
          'conversationId': 'conv-1',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test User',
          'content': 'Hello',
          'sentAt': '2025-12-19T10:30:00.000Z',
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload, isNull);
      });

      test('returns null for missing required fields', () {
        final json = jsonEncode({
          'v': 2,
          'id': 'msg-1',
          // Missing other required fields
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload, isNull);
      });

      test('returns null for invalid json', () {
        final payload = ChatMessagePayload.tryParse('not valid json');

        expect(payload, isNull);
      });

      test('returns null for non-map json', () {
        final payload = ChatMessagePayload.tryParse('"just a string"');

        expect(payload, isNull);
      });

      test('defaults conversation id when empty', () {
        final json = jsonEncode({
          'v': 2,
          'id': 'msg-1',
          'conversationId': '',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test',
          'content': 'Hello',
          'sentAt': '2025-12-19T10:30:00.000Z',
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload!.conversationId, equals('default'));
      });

      test('defaults conversation title when empty', () {
        final json = jsonEncode({
          'v': 2,
          'id': 'msg-1',
          'conversationId': 'conv-1',
          'conversationTitle': '',
          'senderId': 'user-1',
          'senderName': 'Test',
          'content': 'Hello',
          'sentAt': '2025-12-19T10:30:00.000Z',
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload!.conversationTitle, equals('Conversation'));
      });
    });

    group('fallback', () {
      test('creates fallback payload with content', () {
        final payload = ChatMessagePayload.fallback('Test content');

        expect(payload.content, equals('Test content'));
        expect(payload.conversationId, equals('default'));
        expect(payload.conversationTitle, equals('Conversation'));
        expect(payload.senderId, equals('unknown'));
        expect(payload.senderName, equals('Peer'));
      });

      test('generates id for fallback payload', () {
        final payload = ChatMessagePayload.fallback('Content 1');

        expect(payload.id, isNotEmpty);
      });
    });

    group('toJson sentAtMs', () {
      test('includes sentAtMs epoch milliseconds in JSON', () {
        final payload = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test',
          senderId: 'user-1',
          senderName: 'Test',
          content: 'Hello',
          sentAt: testDateTime,
        );

        final json = payload.toJson();

        expect(json['sentAtMs'], equals(testDateTime.millisecondsSinceEpoch));
      });
    });

    group('tryParse sentAtMs fallback', () {
      test('uses sentAtMs when sentAt ISO string is corrupted', () {
        final json = jsonEncode({
          'v': 2,
          'id': 'msg-1',
          'conversationId': 'conv-1',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test User',
          'content': 'Hello',
          'sentAt': 'CORRUPTED_DATE_STRING',
          'sentAtMs': testDateTime.millisecondsSinceEpoch,
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload, isNotNull);
        expect(payload!.sentAt, equals(testDateTime));
      });

      test('preserves original timestamp through sentAtMs on ISO corruption', () {
        // Simulate: host sends at a specific time, but ISO string is corrupted during P2P transfer
        final originalSendTime = DateTime.utc(2025, 6, 15, 14, 30, 45, 123);
        final json = jsonEncode({
          'v': 2,
          'id': 'msg-sync',
          'conversationId': 'conv-1',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test User',
          'content': 'Hello from the past',
          'sentAt': '2025-06-15T14:30:4\x00.123Z', // null byte corruption
          'sentAtMs': originalSendTime.millisecondsSinceEpoch,
        });

        final payload = ChatMessagePayload.tryParse(json);

        // Instead of DateTime.now(), the original time should be preserved via sentAtMs
        expect(payload, isNotNull);
        expect(payload!.sentAt, equals(originalSendTime));
      });

      test(
        'falls back to DateTime.now when both sentAt and sentAtMs are missing',
        () {
          final beforeTest = DateTime.now().toUtc();
          final json = jsonEncode({
            'v': 2,
            'id': 'msg-1',
            'conversationId': 'conv-1',
            'conversationTitle': 'Test',
            'senderId': 'user-1',
            'senderName': 'Test User',
            'content': 'Hello',
            'sentAt': 'invalid',
            // no sentAtMs field
          });

          final payload = ChatMessagePayload.tryParse(json);
          final afterTest = DateTime.now().toUtc();

          expect(payload, isNotNull);
          // Should be approximately now since there's no fallback
          expect(
            payload!.sentAt.isAfter(
              beforeTest.subtract(const Duration(seconds: 1)),
            ),
            isTrue,
          );
          expect(
            payload.sentAt.isBefore(afterTest.add(const Duration(seconds: 1))),
            isTrue,
          );
        },
      );

      test('parses correctly when both sentAt and sentAtMs are valid', () {
        final json = jsonEncode({
          'v': 2,
          'id': 'msg-1',
          'conversationId': 'conv-1',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test User',
          'content': 'Hello',
          'sentAt': '2025-12-19T10:30:00.000Z',
          'sentAtMs': testDateTime.millisecondsSinceEpoch,
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload, isNotNull);
        // Should prefer the ISO string
        expect(payload!.sentAt, equals(testDateTime));
      });

      test(
        'round-trip preserves timestamp via sentAtMs when ISO is corrupted',
        () {
          // Simulate the complete flow: serialize → corrupt ISO → deserialize
          final original = ChatMessagePayload(
            id: 'msg-rt',
            conversationId: 'conv-1',
            conversationTitle: 'Test',
            senderId: 'user-1',
            senderName: 'Test User',
            content: 'Round trip',
            sentAt: testDateTime,
          );

          // Serialize normally (produces both sentAt and sentAtMs)
          final jsonMap = original.toJson();
          // Corrupt the ISO string
          jsonMap['sentAt'] = 'NOT-A-DATE';
          // Re-encode and parse
          final corrupted = jsonEncode(jsonMap);
          final restored = ChatMessagePayload.tryParse(corrupted);

          expect(restored, isNotNull);
          expect(restored!.sentAt, equals(testDateTime));
        },
      );

      test('handles v1 payload without sentAtMs gracefully', () {
        final json = jsonEncode({
          'v': 1,
          'id': 'msg-1',
          'conversationId': 'conv-1',
          'conversationTitle': 'Test',
          'senderId': 'user-1',
          'senderName': 'Test User',
          'content': 'Hello',
          'sentAt': '2025-12-19T10:30:00.000Z',
          // v1 payload — no sentAtMs
        });

        final payload = ChatMessagePayload.tryParse(json);

        expect(payload, isNotNull);
        expect(payload!.sentAt, equals(testDateTime));
      });
    });

    group('round-trip serialization', () {
      test('preserves all fields through encode and parse', () {
        final original = ChatMessagePayload(
          id: 'msg-1',
          conversationId: 'conv-1',
          conversationTitle: 'Test Conversation',
          senderId: 'user-1',
          senderName: 'Display Name',
          content: 'Hello World',
          sentAt: testDateTime,
          senderFullName: 'Full Name',
          senderRole: 'teacher',
          senderGroupName: 'Group A',
          senderProfileImageBase64: 'base64imagedata',
        );

        final encoded = original.encode();
        final restored = ChatMessagePayload.tryParse(encoded);

        expect(restored, isNotNull);
        expect(restored!.id, equals(original.id));
        expect(restored.conversationId, equals(original.conversationId));
        expect(restored.conversationTitle, equals(original.conversationTitle));
        expect(restored.senderId, equals(original.senderId));
        expect(restored.senderName, equals(original.senderName));
        expect(restored.content, equals(original.content));
        expect(restored.senderFullName, equals(original.senderFullName));
        expect(restored.senderRole, equals(original.senderRole));
        expect(restored.senderGroupName, equals(original.senderGroupName));
        expect(
          restored.senderProfileImageBase64,
          equals(original.senderProfileImageBase64),
        );
      });
    });
  });
}
