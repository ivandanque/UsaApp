import 'package:flutter/material.dart';

import '../app/app_navigator.dart';
import '../core/constants/app_constants.dart';
import 'di/app_dependencies.dart';
import 'routes/app_router.dart';

class UsaApp extends StatelessWidget {
  const UsaApp({super.key, required this.initialRoute});

  final String initialRoute;

  @override
  Widget build(BuildContext context) {
    AppDependencies.instance.notificationService.setNavigatorKey(
      AppNavigator.key,
    );
    return MaterialApp(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
      ),
      navigatorKey: AppNavigator.key,
      routes: AppRouter.routes,
      initialRoute: initialRoute,
      onGenerateRoute: AppRouter.onGenerateRoute,
    );
  }
}
