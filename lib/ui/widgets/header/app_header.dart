import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:markit/theme/theme_controller.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';

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
    this.onAbout,
    this.resetEnabled = true,
  });

  final ThemeController themeController;
  final VoidCallback onReset;

  /// Buka halaman About (ikon info di toolbar).
  final VoidCallback? onAbout;
  final bool resetEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;

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
              // Inner highlight tipis — simulasikan refraksi tepi kaca.
              border: Border(
                top: BorderSide(
                  color: isDark
                      ? PdflowColors.inkDark.withValues(alpha: 0.08)
                      : Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
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
                    // Tap brand = kembali ke halaman utama (reset).
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
