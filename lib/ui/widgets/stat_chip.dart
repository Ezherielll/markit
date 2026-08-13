import 'package:flutter/material.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';

/// Small statistic chip (label + value, mono font for numbers).
class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    final surface = isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MarkitSpacing.md,
        vertical: MarkitSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(MarkitSpacing.radiusChip),
        border: Border.all(color: hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: MarkitSpacing.xs),
          ],
          Text(
            value,
            style: TextStyle(
              fontFamily: MarkitTypography.mono,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          ),
          const SizedBox(width: MarkitSpacing.xs),
          Text(label, style: TextStyle(fontSize: 11.5, color: inkMuted)),
        ],
      ),
    );
  }
}
