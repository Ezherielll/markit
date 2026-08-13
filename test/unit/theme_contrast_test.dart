import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/ui/theme/markit_theme.dart';

/// WCAG 2.x relative luminance (0..1) for a color.
/// Note: `Color.r/g/b` are doubles in 0..1 on the current Flutter API.
double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG contrast ratio between two colors.
double _contrast(Color a, Color b) {
  final l1 = _luminance(a);
  final l2 = _luminance(b);
  final hi = math.max(l1, l2);
  final lo = math.min(l1, l2);
  return (hi + 0.05) / (lo + 0.05);
}

/// Composite [fg] (possibly translucent) over [bg], as an opaque color.
Color _blendOver(Color fg, Color bg) => Color.lerp(bg, fg, fg.a)!;

void main() {
  group('theme contrast (dark mode button regression)', () {
    test('dark: onPrimary vs primary >= 4.5 (FilledButton labels readable)', () {
      final scheme = MarkitTheme.dark().colorScheme;
      // Regression: onPrimary used to be inkDark (#EDE8DF) on penBlueDark
      // (#8FB2E8) — ~1.8:1, unreadable FilledButton labels in dark mode.
      expect(_contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5));
    });

    test('light: onPrimary vs primary >= 4.5', () {
      final scheme = MarkitTheme.light().colorScheme;
      expect(_contrast(scheme.primary, scheme.onPrimary),
          greaterThanOrEqualTo(4.5));
    });

    test('dark: outlined button border vs surface >= 3.0 (non-text contrast)',
        () {
      final theme = MarkitTheme.dark();
      final side = theme.outlinedButtonTheme.style!.side!.resolve({});
      final scheme = theme.colorScheme;
      // Regression: border used to be hairlineDark on surfaceDark — ~1.4:1,
      // the outlined button was practically invisible in dark mode.
      final border = _blendOver(side!.color, scheme.surface);
      expect(_contrast(border, scheme.surface), greaterThanOrEqualTo(3.0));
    });

    test('dark: onSurface vs surface >= 4.5 (base text)', () {
      final scheme = MarkitTheme.dark().colorScheme;
      expect(_contrast(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5));
    });
  });
}
