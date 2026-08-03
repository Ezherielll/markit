import 'package:flutter/material.dart';

import 'isolate/conversion_controller.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/pdflow_theme.dart';

class PdflowApp extends StatelessWidget {
  const PdflowApp({super.key, this.controller});

  /// Dapat di-inject untuk widget test.
  final ConversionController? controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'pdflow',
      debugShowCheckedModeBanner: false,
      theme: PdflowTheme.light(),
      darkTheme: PdflowTheme.dark(),
      home: HomeScreen(controller: controller ?? IsolateConversionController()),
    );
  }
}
