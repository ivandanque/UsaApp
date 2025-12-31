import 'package:flutter_test/flutter_test.dart';
import 'package:usaapp/src/app/di/app_dependencies.dart';

void main() {
  test('import app_dependencies', () {
    // If import caused side-effects that keep VM alive, this test may hang.
    expect(AppDependencies.instance, isNotNull);
  });
}
