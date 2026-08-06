import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:pdflow/theme/theme_controller.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';

import 'brand_lockup.dart';
import 'header_toolbar.dart';

/// Header aplikasi — brand lockup (kiri) + toolbar aksi (kanan).
/// Status pill kontekstual dipindah ke sudut kiri bawah layar (HomeScreen).
/// Latar glass translucent + divider tipis.
/// Responsive: subtitle brand collapse di viewport sempit.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.themeController,
    required this.onReset,
    this.resetEnabled = true,
  });

  final ThemeController themeController;
  final VoidCallback onReset;
  final bool resetEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;

    return ClipRect(
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: hairline, width: 1),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Container(
            color: surface.withValues(alpha: isDark ? 0.78 : 0.72),
            padding: const EdgeInsets.symmetric(
              horizontal: PdflowSpacing.xxl,
              vertical: PdflowSpacing.md,
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                return Row(
                  children: [
                    // Brand lockup fleksibel — subtitle collapse di compact.
                    Flexible(
                      child: BrandLockup(showSubtitle: !compact),
                    ),
                    const Spacer(),
                    HeaderToolbar(
                      themeController: themeController,
                      onReset: onReset,
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
