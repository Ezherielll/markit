import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';
import 'package:pdflow/ui/widgets/stat_chip.dart';

/// Panel progress konversi (FR-08): persen serif besar, bar animasi,
/// phase label, chips waktu & pages/s, tombol cancel.
class ProgressPanel extends StatelessWidget {
  const ProgressPanel({
    super.key,
    required this.currentPage,
    required this.totalPages,
    required this.elapsed,
    required this.onCancel,
    this.passTwo = false,
  });

  final int currentPage;
  final int totalPages;
  final Duration elapsed;
  final VoidCallback onCancel;

  /// true = phase 2 (convert); false = phase 1 (reading).
  final bool passTwo;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    final surface = isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight;

    final progress = totalPages > 0 ? currentPage / totalPages : 0.0;
    final pagesPerSec = elapsed.inSeconds > 0
        ? currentPage / elapsed.inSeconds
        : currentPage.toDouble();

    return Container(
      padding: const EdgeInsets.all(PdflowSpacing.xl),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '${(progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(
                  fontFamily: PdflowTypography.display,
                  fontSize: 44,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  fontVariations: const [FontVariation('opsz', 48)],
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: PdflowSpacing.lg),
                ),
                child: const Text(Strings.cancel),
              ),
            ],
          ),
          const SizedBox(height: PdflowSpacing.md),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress.clamp(0.0, 1.0)),
            duration: const Duration(milliseconds: 250),
            builder: (context, value, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: value,
                minHeight: 6,
                backgroundColor: hairline,
              ),
            ),
          ),
          const SizedBox(height: PdflowSpacing.md),
          Text(
            passTwo
                ? Strings.phaseConverting.replaceFirst('%d', '$currentPage')
                    .replaceFirst('%d', '$totalPages')
                : Strings.phaseReading,
            style: TextStyle(color: ink, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: PdflowSpacing.lg),
          Wrap(
            spacing: PdflowSpacing.sm,
            runSpacing: PdflowSpacing.sm,
            children: [
              StatChip(
                label: Strings.pagesLabel,
                value: '$currentPage / $totalPages',
              ),
              StatChip(
                label: Strings.statsTime,
                value: _formatElapsed(elapsed),
              ),
              StatChip(
                label: Strings.statsPagesPerSec,
                value: pagesPerSec.toStringAsFixed(1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _formatElapsed(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}
