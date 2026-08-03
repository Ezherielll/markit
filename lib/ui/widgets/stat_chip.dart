import 'package:flutter/material.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';

/// Chip statistik kecil (label + nilai, font mono untuk angka).
class StatChip extends StatelessWidget {
  const StatChip({super.key, required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    final surface = isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PdflowSpacing.md,
        vertical: PdflowSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(PdflowSpacing.radiusChip),
        border: Border.all(color: hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: PdflowSpacing.xs),
          ],
          Text(
            value,
            style: TextStyle(
              fontFamily: PdflowTypography.mono,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: ink,
            ),
          ),
          const SizedBox(width: PdflowSpacing.xs),
          Text(label, style: TextStyle(fontSize: 11.5, color: inkMuted)),
        ],
      ),
    );
  }
}
