import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';

/// Status kontekstual tengah header — pill/breadcrumb ringkas.
/// Menunjukkan keadaan workspace: ready / files loaded / processing / done.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.controller, this.showLabel = true});

  final ConversionController controller;

  /// Sembunyikan label di viewport sempit (hanya ikon).
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
    final scheme = Theme.of(context).colorScheme;

    final status = _statusFor(controller);
    final (icon, color) = switch (status.kind) {
      _StatusKind.ready => (Icons.check_circle_outline, scheme.primary),
      _StatusKind.loaded => (Icons.description_outlined, inkMuted),
      _StatusKind.processing => (Icons.sync, scheme.primary),
      _StatusKind.done => (Icons.verified_outlined, scheme.primary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PdflowSpacing.md,
        vertical: PdflowSpacing.xs + 2,
      ),
      decoration: BoxDecoration(
        color: isDark ? PdflowColors.surfaceRaisedDark : PdflowColors.surfaceRaisedLight,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          if (showLabel) ...[
            const SizedBox(width: 6),
            Text(
              status.label,
              style: TextStyle(
                fontFamily: PdflowTypography.ui,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: isDark ? PdflowColors.inkDark : PdflowColors.inkLight,
              ),
            ),
          ],
        ],
      ),
    );
  }

  _Status _statusFor(ConversionController c) {
    if (c.isRunning) {
      return _Status(
        _StatusKind.processing,
        Strings.statusProcessing.replaceFirst('%d', '${c.queue.length}'),
      );
    }
    if (c.queue.isEmpty) {
      return const _Status(_StatusKind.ready, Strings.statusReady);
    }
    final done = c.doneCount;
    final allFinal = c.queue.every((f) => f.status != JobStatus.queued);
    if (allFinal) {
      return _Status(
        _StatusKind.done,
        done > 0
            ? Strings.statusConverted.replaceFirst('%d', '$done')
            : Strings.statusBatchComplete,
      );
    }
    return _Status(
      _StatusKind.loaded,
      Strings.statusFilesLoaded.replaceFirst('%d', '${c.queue.length}'),
    );
  }
}

enum _StatusKind { ready, loaded, processing, done }

class _Status {
  const _Status(this.kind, this.label);
  final _StatusKind kind;
  final String label;
}
