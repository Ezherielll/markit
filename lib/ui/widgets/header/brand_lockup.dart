import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';

/// Brand lockup: ikon dokumen modern + nama "MarkIt" + subtitle deskriptif.
/// Bagian kiri header — membangun identitas produk.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.showSubtitle = true});

  /// Sembunyikan subtitle di viewport sempit (responsive).
  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        // Ikon dokumen modern dalam tile rounded.
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                scheme.primary,
                scheme.primary.withValues(alpha: 0.72),
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.25),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Icon(
            Icons.description_rounded,
            size: 20,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: PdflowSpacing.md),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Strings.appTitle,
                style: TextStyle(
                  fontFamily: PdflowTypography.display,
                  fontSize: 20,
                  height: 1.1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.2,
                  color: ink,
                ),
              ),
              if (showSubtitle) ...[
                const SizedBox(height: 1),
                Text(
                  Strings.headerSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PdflowTypography.ui,
                    fontSize: 11.5,
                    height: 1.2,
                    color: inkMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
