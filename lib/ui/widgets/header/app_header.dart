import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:markit/theme/theme_controller.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';

import 'brand_lockup.dart';
import 'header_toolbar.dart';

/// Application header — brand lockup (left) + action toolbar (right).
/// Contextual status pill moved to bottom-left of screen (HomeScreen).
/// Translucent glass background + thin divider.
/// Responsive: brand subtitle collapses on narrow viewports.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.themeController,
    required this.onReset,
    this.onAbout,
    this.resetEnabled = true,
  });

  final ThemeController themeController;
  final VoidCallback onReset;

  /// Open About screen (info icon in toolbar).
  final VoidCallback? onAbout;
  final bool resetEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;

    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: hairline, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: ink.withValues(alpha: isDark ? 0.16 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            decoration: BoxDecoration(
              color: surface.withValues(alpha: isDark ? 0.78 : 0.72),
              // Thin inner highlight — simulates glass edge refraction.
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? MarkitColors.inkDark.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: MarkitSpacing.xxl,
              vertical: MarkitSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                return Row(
                  children: [
                    // Flexible brand lockup — subtitle collapses on compact viewports.
                    // Tapping brand returns to home screen (reset).
                    Flexible(
                      child: BrandLockup(
                        showSubtitle: !compact,
                        onTap: resetEnabled ? onReset : null,
                      ),
                    ),
                    const Spacer(),
                    HeaderToolbar(
                      themeController: themeController,
                      onReset: onReset,
                      onAbout: onAbout,
                      resetEnabled: resetEnabled,
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
