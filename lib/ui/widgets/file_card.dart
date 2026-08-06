import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/isolate/conversion_controller.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';

/// Kartu satu file dalam queue batch: nama, ukuran, pages, status chip,
/// tombol hapus (opsional). Hover: border accent + surface shift halus.
class FileCard extends StatefulWidget {
  const FileCard({
    super.key,
    required this.job,
    this.showStatus = false,
    this.onRemove,
  });

  final QueuedFile job;

  /// Tampilkan status chip (queued/running/done/failed/cancelled).
  final bool showStatus;

  /// Callback tombol hapus (null = tanpa tombol).
  final VoidCallback? onRemove;

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    final primary = Theme.of(context).colorScheme.primary;

    final job = widget.job;
    final sizeBytes = job.input.sizeBytes;
    final size = sizeBytes == null
        ? null
        : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    final baseBorder = job.status == JobStatus.failed
        ? (isDark ? PdflowColors.stampRedDark : PdflowColors.stampRedLight)
        : hairline;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: widget.onRemove != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(PdflowSpacing.lg),
        decoration: BoxDecoration(
          color: _hovered
              ? primary.withValues(alpha: isDark ? 0.06 : 0.04)
              : (isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight),
          borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
          border: Border.all(
            color: _hovered && widget.onRemove != null ? primary : baseBorder,
          ),
        ),
        child: Row(
        children: [
          Container(
            width: 44,
            height: 56,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.picture_as_pdf_outlined,
              size: 26,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: PdflowSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(job.fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PdflowTypography.mono,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    )),
                const SizedBox(height: 4),
                Text(
                  [
                    ?size,
                    if (job.pageCount != null)
                      '${job.pageCount} ${Strings.pagesLabel}',
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 12.5, color: inkMuted),
                ),
                if (widget.showStatus && job.status == JobStatus.failed) ...[
                  const SizedBox(height: 4),
                  Text(
                    _errorText(job),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark
                          ? PdflowColors.stampRedDark
                          : PdflowColors.stampRedLight,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (widget.showStatus) ...[
            const SizedBox(width: PdflowSpacing.md),
            _StatusChip(status: job.status),
          ],
          if (widget.onRemove != null) ...[
            const SizedBox(width: PdflowSpacing.xs),
            IconButton(
              onPressed: widget.onRemove,
              icon: const Icon(Icons.close, size: 18),
              tooltip: Strings.removeFile,
            ),
          ],
        ],
        ),
      ),
    );
  }

  static String _errorText(QueuedFile job) {
    return switch (job.errorType) {
      'encrypted' => Strings.errorEncrypted,
      'noText' => Strings.errorNoText,
      'corrupt' => Strings.errorCorrupt,
      _ => job.errorMessage ?? Strings.errorGeneric.replaceFirst('%s', ''),
    };
  }
}

/// Chip status kecil untuk file dalam batch.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (label, color) = switch (status) {
      JobStatus.queued => (
          Strings.fileQueued,
          isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight,
        ),
      JobStatus.running => (
          Strings.fileRunning,
          Theme.of(context).colorScheme.primary,
        ),
      JobStatus.done => (
          Strings.fileDone,
          isDark ? PdflowColors.stampGreenDark : PdflowColors.stampGreenLight,
        ),
      JobStatus.failed => (
          Strings.fileFailed,
          isDark ? PdflowColors.stampRedDark : PdflowColors.stampRedLight,
        ),
      JobStatus.cancelled => (
          Strings.fileCancelled,
          isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: PdflowSpacing.sm,
        vertical: PdflowSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(PdflowSpacing.radiusChip),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
