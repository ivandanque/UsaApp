import 'package:flutter/material.dart';

import 'src/app/di/app_dependencies.dart';
import 'src/app/usa_app.dart';
import 'src/core/services/onboarding_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppDependencies.instance.init();
  await AppDependencies.instance.initializeNotificationService();
  final initialRoute = await OnboardingService().getInitialRoute();

  runApp(UsaApp(initialRoute: initialRoute));
}
