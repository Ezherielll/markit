import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize pdfrx — desktop: cache dir; web: WASM engine worker.
  // Idempotent & safe for all platforms.
  await pdfrxFlutterInitialize();

  // Load theme preferences before runApp.
  final themeController = ThemeController();
  await themeController.load();

  runApp(MarkitApp(themeController: themeController));
}
