import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Inisialisasi pdfrx — desktop: cache dir; web: WASM engine worker.
  // Idempotent & aman untuk semua platform (M5).
  await pdfrxFlutterInitialize();

  runApp(const PdflowApp());
}
