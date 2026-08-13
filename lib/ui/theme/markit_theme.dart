import 'package:flutter/material.dart';

import 'palette.dart';
import 'spacing.dart';
import 'typography.dart';

/// "Document Studio" theme — light & dark, built on Material 3.
abstract final class MarkitTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = isLight
        ? const ColorScheme.light(
            primary: MarkitColors.penBlueLight,
            onPrimary: Colors.white,
            surface: MarkitColors.surfaceLight,
            onSurface: MarkitColors.inkLight,
            surfaceContainerHighest: MarkitColors.paperLight,
            onSurfaceVariant: MarkitColors.inkMutedLight,
            error: MarkitColors.stampRedLight,
            outline: MarkitColors.hairlineLight,
          )
        : const ColorScheme.dark(
            primary: MarkitColors.penBlueDark,
            onPrimary: MarkitColors.inkDark,
            surface: MarkitColors.surfaceDark,
            onSurface: MarkitColors.inkDark,
            surfaceContainerHighest: MarkitColors.surfaceRaisedDark,
            onSurfaceVariant: MarkitColors.inkMutedDark,
            error: MarkitColors.stampRedDark,
            outline: MarkitColors.hairlineDark,
          );

    final ink = isLight ? MarkitColors.inkLight : MarkitColors.inkDark;
    final inkMuted = isLight ? MarkitColors.inkMutedLight : MarkitColors.inkMutedDark;
    final paper = isLight ? MarkitColors.paperLight : MarkitColors.paperDark;
    final hairline = isLight ? MarkitColors.hairlineLight : MarkitColors.hairlineDark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      fontFamily: MarkitTypography.ui,
      textTheme: MarkitTypography.textTheme(ink, inkMuted),
      dividerColor: hairline,
      splashFactory: InkRipple.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: MarkitSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
          ),
          textStyle: const TextStyle(
            fontFamily: MarkitTypography.ui,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: MarkitSpacing.xl),
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
          ),
          textStyle: const TextStyle(
            fontFamily: MarkitTypography.ui,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(MarkitSpacing.radiusChip),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
          borderSide: BorderSide(color: hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight
            ? MarkitColors.surfaceRaisedLight
            : MarkitColors.surfaceRaisedDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarkitSpacing.radiusDropzone),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(MarkitSpacing.radiusCard)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? MarkitColors.inkLight : MarkitColors.surfaceRaisedDark,
        contentTextStyle: TextStyle(
          color: isLight ? MarkitColors.paperLight : MarkitColors.inkDark,
          fontFamily: MarkitTypography.ui,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: hairline,
      ),
    );
  }
}
