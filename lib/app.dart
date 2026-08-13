import 'package:flutter/material.dart';

import 'isolate/conversion_controller.dart';
import 'theme/theme_controller.dart';
import 'ui/screens/home_screen.dart';
import 'ui/theme/markit_theme.dart';

class MarkitApp extends StatefulWidget {
  const MarkitApp({super.key, this.controller, this.themeController});

  /// Can be injected for widget tests.
  final ConversionController? controller;

  /// Theme controller. Null → created internally (system default).
  final ThemeController? themeController;

  @override
  State<MarkitApp> createState() => _MarkitAppState();
}

class _MarkitAppState extends State<MarkitApp> {
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
        theme: MarkitTheme.light(),
        darkTheme: MarkitTheme.dark(),
        themeMode: _theme.mode,
        home: HomeScreen(controller: _controller, themeController: _theme),
      ),
    );
  }
}
