import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';
import 'package:markit/ui/widgets/markit_mark.dart';

/// Brand lockup: MarkIt [M] logo + "MarkIt" title + descriptive subtitle.
/// Left side of header — establishes product identity.
/// If [onTap] is provided, lockup is clickable (returns to home / reset)
/// with hover & ripple effect.
class BrandLockup extends StatelessWidget {
  const BrandLockup({super.key, this.showSubtitle = true, this.onTap});

  /// Hide subtitle on narrow viewports (responsive).
  final bool showSubtitle;

  /// Tap brand → reset to home screen. Null = non-clickable.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;
    final scheme = Theme.of(context).colorScheme;

    final lockup = Row(
      children: [
        const MarkItMark(size: 36),
        const SizedBox(width: MarkitSpacing.md),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Strings.appTitle,
                style: TextStyle(
                  fontFamily: MarkitTypography.display,
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
                    fontFamily: MarkitTypography.ui,
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

    if (onTap == null) return lockup;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        hoverColor: scheme.primary.withValues(alpha: 0.06),
        splashColor: scheme.primary.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: lockup,
        ),
      ),
    );
  }
}
