import 'package:flutter/material.dart';

import 'isolate/conversion_controller.dart';
import 'theme/theme_controller.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/markit_theme.dart';

class PdflowApp extends StatefulWidget {
  const PdflowApp({super.key, this.controller, this.themeController});

  /// Dapat di-inject untuk widget test.
  final ConversionController? controller;

  /// Controller tema (M7). Null → dibuat internal (system default).
  final ThemeController? themeController;

  @override
  State<PdflowApp> createState() => _PdflowAppState();
}

class _PdflowAppState extends State<PdflowApp> {
  late final ThemeController _theme = widget.themeController ?? ThemeController();
  late final ConversionController _controller =
      widget.controller ?? BatchConversionController();

  @override
  void initState() {
    super.initState();
    _theme.load();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _theme,
      builder: (context, _) => MaterialApp(
        title: 'MarkIt',
        debugShowCheckedModeBanner: false,
        theme: PdflowTheme.light(),
        darkTheme: PdflowTheme.dark(),
        themeMode: _theme.mode,
        home: HomeScreen(controller: _controller, themeController: _theme),
      ),
    );
  }
}
