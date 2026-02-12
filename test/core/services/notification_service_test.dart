import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:usaapp/src/core/models/room_summary.dart';
import 'package:usaapp/src/core/services/notification_service.dart';

class TestNotificationPlugin implements NotificationPlugin {
	final List<_ShowCall> calls = [];

	@override
	Future<void> show({
		required int id,
		String? title,
		String? body,
		NotificationDetails? notificationDetails,
		String? payload,
	}) async {
		calls.add(_ShowCall(id: id, title: title, body: body, payload: payload));
	}
}

class _ShowCall {
	const _ShowCall({required this.id, this.title, this.body, this.payload});
	final int id;
	final String? title;
	final String? body;
	final String? payload;
}

void main() {
	group('NotificationService (adapter)', () {
		late TestNotificationPlugin plugin;
		late NotificationService svc;

		setUp(() {
			plugin = TestNotificationPlugin();
			svc = NotificationService.withPlugin(plugin: plugin);
		});

		test('does not emit when not initialized', () async {
			await svc.notifyRoomsFound(const <RoomSummary>[]);
			expect(plugin.calls, isEmpty);
		});

		test('rooms notification single room', () async {
			await svc.initialize();
			await svc.notifyRoomsFound(const [RoomSummary(roomTitle: 'r', hostName: 'h')]);
			expect(plugin.calls, hasLength(1));
			final c = plugin.calls.first;
			expect(c.id, equals(9001));
			expect(c.title, contains('r'));
			expect(c.payload, equals('rooms'));
		});

		test('connected/disconnected notifications', () async {
			await svc.initialize();
			await svc.notifyConnected('roomA', 'hostA');
			await svc.notifyDisconnected();
			expect(plugin.calls.length, equals(2));
			expect(plugin.calls[0].id, equals(9002));
			expect(plugin.calls[1].id, equals(9003));
		});
	});
}

