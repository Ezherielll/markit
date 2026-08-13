import 'package:flutter/material.dart';

/// "Document Studio" typography: Fraunces (display serif), Inter (UI),
/// JetBrains Mono (data/preview). Fonts are bundled as assets — 100% offline-safe.
abstract final class MarkitTypography {
  static const display = 'Fraunces';
  static const ui = 'Inter';
  static const mono = 'JetBrainsMono';

  /// Tabular numbers (monospace figures) for data-heavy UI — numbers do not
  /// shift horizontally when values change (elapsed time, pages, percent).
  static const List<FontFeature> tabularFigures = [
    FontFeature.tabularFigures(),
  ];

  /// TextTheme based on color palette (light/dark).
  static TextTheme textTheme(Color ink, Color inkMuted) {
    const base = TextTheme();
    return base
        .copyWith(
          displayLarge: const TextStyle(
            fontFamily: display,
            fontSize: 56,
            height: 1.05,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
            fontFeatures: tabularFigures,
            fontVariations: [FontVariation('opsz', 72)],
          ),
          displayMedium: TextStyle(
            fontFamily: display,
            fontSize: 40,
            height: 1.1,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
            fontFeatures: tabularFigures,
            fontVariations: const [FontVariation('opsz', 48)],
            color: ink,
          ),
          headlineMedium: TextStyle(
            fontFamily: display,
            fontSize: 28,
            height: 1.15,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
            fontFeatures: tabularFigures,
            fontVariations: const [FontVariation('opsz', 32)],
            color: ink,
          ),
          titleLarge: TextStyle(
            fontFamily: display,
            fontSize: 20,
            height: 1.2,
            fontWeight: FontWeight.w600,
            fontFeatures: tabularFigures,
            color: ink,
          ),
          titleMedium: TextStyle(
            fontFamily: ui,
            fontSize: 16,
            height: 1.3,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
          bodyLarge: TextStyle(
            fontFamily: ui,
            fontSize: 16,
            height: 1.55,
            fontWeight: FontWeight.w400,
            color: ink,
          ),
          bodyMedium: TextStyle(
            fontFamily: ui,
            fontSize: 14,
            height: 1.5,
            fontWeight: FontWeight.w400,
            color: ink,
          ),
          bodySmall: TextStyle(
            fontFamily: ui,
            fontSize: 12,
            height: 1.45,
            fontWeight: FontWeight.w400,
            color: inkMuted,
          ),
          labelLarge: const TextStyle(
            fontFamily: ui,
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            fontFeatures: tabularFigures,
          ),
          labelMedium: TextStyle(
            fontFamily: ui,
            fontSize: 12,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
            fontFeatures: tabularFigures,
            color: inkMuted,
          ),
          labelSmall: TextStyle(
            fontFamily: ui,
            fontSize: 10.5,
            height: 1.3,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.6,
            color: inkMuted,
          ),
        )
        .apply(bodyColor: ink, displayColor: ink);
  }

  /// Monospace style for data/preview (fontFamily mono, size set by caller).
  static const TextStyle monoStyle = TextStyle(
    fontFamily: mono,
    fontVariations: [FontVariation('wght', 400)],
  );
}
