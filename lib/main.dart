import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi pdfrx — desktop: cache dir; web: WASM engine worker.
  // Idempotent & aman untuk semua platform (M5).
  await pdfrxFlutterInitialize();

  // Muat preferensi tema sebelum runApp (M7).
  final themeController = ThemeController();
  await themeController.load();

  runApp(PdflowApp(themeController: themeController));
}
