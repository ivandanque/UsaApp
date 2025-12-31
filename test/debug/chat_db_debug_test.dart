import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';
// Removed unused import

void main() {
  test('db write/watch debug', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues(const <String, Object>{});
    await AppDependencies.instance.init(executor: NativeDatabase.memory());

    final store = AppDependencies.instance.conversationStore;
    final conversation = await store.createConversation('Debug Conversation');

    final controller = AppDependencies.instance.createChatController(
      conversation: conversation,
    );
    await controller.start();

    // Give watcher time to subscribe
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Send a message
    await controller.sendLocalMessage('Debug message');

    // Wait a bit for streams and prints
    await Future<void>.delayed(const Duration(seconds: 2));

    // Cleanup
    await store.deleteConversation(conversation.id);
  }, timeout: Timeout.none);
}
