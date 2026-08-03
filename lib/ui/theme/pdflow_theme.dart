import 'package:flutter/material.dart';

import 'palette.dart';
import 'spacing.dart';
import 'typography.dart';

/// Tema "Document Studio" — light & dark, dibangun di atas Material 3.
abstract final class PdflowTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isLight = brightness == Brightness.light;
    final scheme = isLight
        ? const ColorScheme.light(
            primary: PdflowColors.penBlueLight,
            onPrimary: Colors.white,
            surface: PdflowColors.surfaceLight,
            onSurface: PdflowColors.inkLight,
            surfaceContainerHighest: PdflowColors.paperLight,
            onSurfaceVariant: PdflowColors.inkMutedLight,
            error: PdflowColors.stampRedLight,
            outline: PdflowColors.hairlineLight,
          )
        : const ColorScheme.dark(
            primary: PdflowColors.penBlueDark,
            onPrimary: PdflowColors.inkDark,
            surface: PdflowColors.surfaceDark,
            onSurface: PdflowColors.inkDark,
            surfaceContainerHighest: PdflowColors.surfaceRaisedDark,
            onSurfaceVariant: PdflowColors.inkMutedDark,
            error: PdflowColors.stampRedDark,
            outline: PdflowColors.hairlineDark,
          );

    final ink = isLight ? PdflowColors.inkLight : PdflowColors.inkDark;
    final inkMuted = isLight ? PdflowColors.inkMutedLight : PdflowColors.inkMutedDark;
    final paper = isLight ? PdflowColors.paperLight : PdflowColors.paperDark;
    final hairline = isLight ? PdflowColors.hairlineLight : PdflowColors.hairlineDark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: paper,
      fontFamily: PdflowTypography.ui,
      textTheme: PdflowTypography.textTheme(ink, inkMuted),
      dividerColor: hairline,
      splashFactory: InkRipple.splashFactory,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: PdflowSpacing.xl),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
          ),
          textStyle: const TextStyle(
            fontFamily: PdflowTypography.ui,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: PdflowSpacing.xl),
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
          ),
          textStyle: const TextStyle(
            fontFamily: PdflowTypography.ui,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PdflowSpacing.radiusChip),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
          borderSide: BorderSide(color: hairline),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isLight
            ? PdflowColors.surfaceRaisedLight
            : PdflowColors.surfaceRaisedDark,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PdflowSpacing.radiusDropzone),
        ),
      ),
      cardTheme: const CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(PdflowSpacing.radiusCard)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isLight ? PdflowColors.inkLight : PdflowColors.surfaceRaisedDark,
        contentTextStyle: TextStyle(
          color: isLight ? PdflowColors.paperLight : PdflowColors.inkDark,
          fontFamily: PdflowTypography.ui,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: hairline,
      ),
    );
  }
}
