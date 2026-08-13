import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme controller (light/dark/system) with cross-session persistence.
/// Desktop: SharedPreferences on disk; Web: localStorage.
class ThemeController extends ChangeNotifier {
  ThemeController({ThemeMode initial = ThemeMode.system})
      : _mode = initial;

  static const _prefKey = 'theme_mode';

  ThemeMode _mode;
  ThemeMode get mode => _mode;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);
      if (saved != null) {
        _mode = switch (saved) {
          'light' => ThemeMode.light,
          'dark' => ThemeMode.dark,
          _ => ThemeMode.system,
        };
        notifyListeners();
      }
    } catch (_) {
      // Persistence failure → default to system, non-fatal.
    }
  }

  /// Cycle: light → dark → system → light…
  void cycle() {
    _mode = switch (_mode) {
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
      ThemeMode.system => ThemeMode.light,
    };
    notifyListeners();
    _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefKey,
        switch (_mode) {
          ThemeMode.light => 'light',
          ThemeMode.dark => 'dark',
          ThemeMode.system => 'system',
        },
      );
    } catch (_) {
      // Best-effort.
    }
  }
}
