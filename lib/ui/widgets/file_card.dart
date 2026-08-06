import 'package:flutter/material.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';

/// Ikon per format input (M5 multi-format).
IconData iconForFormat(InputFormat format) => switch (format) {
      InputFormat.pdf => Icons.picture_as_pdf_outlined,
      InputFormat.text => Icons.description_outlined,
      InputFormat.markdown => Icons.notes,
      InputFormat.csv => Icons.table_chart_outlined,
      InputFormat.json => Icons.data_object,
      InputFormat.xml => Icons.code,
      InputFormat.html => Icons.language,
      InputFormat.docx => Icons.description,
      InputFormat.xlsx => Icons.table_chart,
      InputFormat.pptx => Icons.slideshow_outlined,
      InputFormat.epub => Icons.menu_book_outlined,
      InputFormat.zip => Icons.folder_zip_outlined,
      InputFormat.image => Icons.image_outlined,
      InputFormat.audio => Icons.audiotrack_outlined,
      InputFormat.unknown => Icons.insert_drive_file_outlined,
    };

/// Item daftar file: ikon, nama, ukuran, status chip, progress bar,
/// download per-file (web, saat selesai) & tombol hapus. Selectable.
class FileCard extends StatefulWidget {
  const FileCard({
    super.key,
    required this.job,
    this.showStatus = false,
    this.onRemove,
    this.onDownload,
    this.onTap,
    this.selected = false,
    this.progress,
    this.phase = 1,
  });

  final QueuedFile job;
  final bool showStatus;
  final VoidCallback? onRemove;
  final VoidCallback? onDownload;
  final VoidCallback? onTap;
  final bool selected;

  /// Progress 0..1 (job running); null = indeterminate (total belum diketahui).
  final double? progress;

  /// 0 = pass 1 (reading), 1 = pass 2 (converting) — untuk label phase.
  final int phase;

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

    final isInteractive = widget.onTap != null || widget.onRemove != null;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: isInteractive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(PdflowSpacing.md),
        decoration: BoxDecoration(
          color: widget.selected
              ? primary.withValues(alpha: isDark ? 0.12 : 0.08)
              : _hovered
                  ? primary.withValues(alpha: isDark ? 0.06 : 0.04)
                  : (isDark
                      ? PdflowColors.surfaceDark
                      : PdflowColors.surfaceLight),
          borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
          border: Border.all(
            color: widget.selected
                ? primary
                : _hovered && isInteractive
                    ? primary
                    : baseBorder,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 44,
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Icon(
                      iconForFormat(job.input.format),
                      size: 22,
                      color: primary,
                    ),
                  ),
                  const SizedBox(width: PdflowSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(job.fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: PdflowTypography.mono,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                              color: ink,
                            )),
                        const SizedBox(height: 2),
                        Text(
                          [
                            ?size,
                            if (job.pageCount != null)
                              '${job.pageCount} ${Strings.pagesLabel}',
                          ].join('  ·  '),
                          style: TextStyle(
                            fontSize: 11,
                            fontFeatures: PdflowTypography.tabularFigures,
                            color: inkMuted,
                          ),
                        ),
                        if (widget.showStatus &&
                            job.status == JobStatus.failed) ...[
                          const SizedBox(height: 2),
                          Text(
                            _errorText(job),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10.5,
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
                    const SizedBox(width: PdflowSpacing.sm),
                    _StatusChip(status: job.status),
                  ],
                  if (widget.onDownload != null) ...[
                    const SizedBox(width: 2),
                    IconButton(
                      onPressed: widget.onDownload,
                      icon: const Icon(Icons.download_outlined, size: 17),
                      tooltip: Strings.download,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                  if (widget.onRemove != null) ...[
                    const SizedBox(width: 2),
                    IconButton(
                      onPressed: widget.onRemove,
                      icon: const Icon(Icons.close, size: 17),
                      tooltip: Strings.removeFile,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ],
              ),
              if (widget.progress != null || job.status == JobStatus.running) ...[
                const SizedBox(height: PdflowSpacing.sm),
                // Label phase + metadata progress (page X of Y · %).
                Row(
                  children: [
                    Text(
                      widget.phase == 0
                          ? Strings.phaseReadingShort
                          : Strings.phaseConvertingShort,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: inkMuted,
                      ),
                    ),
                    const Spacer(),
                    if (widget.progress != null)
                      Text(
                        _progressText(job, widget.progress!),
                        style: TextStyle(
                          fontFamily: PdflowTypography.mono,
                          fontSize: 10,
                          fontFeatures: PdflowTypography.tabularFigures,
                          color: inkMuted,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 3),
                // Bar animasi halus; indeterminate saat total belum diketahui.
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: SizedBox(
                    height: 5,
                    child: widget.progress == null
                        ? const LinearProgressIndicator(minHeight: 5)
                        : TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 0,
                              end: widget.progress!.clamp(0.0, 1.0),
                            ),
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOut,
                            builder: (context, value, _) =>
                                LinearProgressIndicator(
                              value: value,
                              minHeight: 5,
                              backgroundColor: hairline,
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _errorText(QueuedFile job) {
    return switch (job.errorType) {
      'encrypted' => Strings.errorEncrypted,
      'noText' => Strings.errorNoText,
      'corrupt' => Strings.errorCorrupt,
      'unsupported' => Strings.errorUnsupported,
      _ => job.errorMessage ?? Strings.errorGeneric.replaceFirst('%s', ''),
    };
  }

  /// Metadata progress: "12 of 300 pages · 4%" (tabular figures).
  static String _progressText(QueuedFile job, double fraction) {
    final page = job.currentPage ?? 0;
    final total = job.totalPages ?? 0;
    final pct = (fraction * 100).clamp(0, 100).round();
    final pages = total > 0
        ? '${Strings.pageOf.replaceFirst('%d', '$page').replaceFirst('%d', '$total')} · '
        : '';
    return '$pages$pct%';
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
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
