import 'package:flutter/material.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';
import 'package:markit/ui/widgets/job_error_view.dart';

/// Icon per input format — one icon per format family.
IconData iconForFormat(InputFormat format) => switch (format) {
      InputFormat.pdf => Icons.picture_as_pdf_outlined,
      InputFormat.word => Icons.description_outlined,
      InputFormat.powerpoint => Icons.slideshow_outlined,
      InputFormat.excel => Icons.table_chart_outlined,
      InputFormat.opendocument => Icons.article_outlined,
      InputFormat.rtf => Icons.notes,
      InputFormat.epub => Icons.menu_book_outlined,
      InputFormat.csv => Icons.table_rows_outlined,
      InputFormat.unknown => Icons.insert_drive_file_outlined,
    };

/// File list item card: icon, name, size, status chip, progress bar,
/// per-file download (web, on completion) & remove button. Selectable.
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

  /// Progress 0..1 (running job); null = indeterminate (total unknown yet).
  final double? progress;

  /// 0 = pass 1 (reading), 1 = pass 2 (converting) — for phase label.
  final int phase;

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    final primary = Theme.of(context).colorScheme.primary;

    final job = widget.job;
    final sizeBytes = job.input.sizeBytes;
    final size = sizeBytes == null
        ? null
        : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';

    final baseBorder = job.status == JobStatus.failed
        ? (isDark ? MarkitColors.stampRedDark : MarkitColors.stampRedLight)
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
        padding: const EdgeInsets.all(MarkitSpacing.md),
        decoration: BoxDecoration(
          color: _cardColor(isDark, primary),
          borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
          border: Border.all(
            color: _cardBorder(primary, baseBorder, isInteractive),
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _buildIcon(primary),
                  const SizedBox(width: MarkitSpacing.md),
                  Expanded(child: _buildInfo(ink, inkMuted, size)),
                  ..._buildActions(),
                ],
              ),
              if (widget.progress != null || job.status == JobStatus.running)
                ..._buildProgress(inkMuted, hairline),
            ],
          ),
        ),
      ),
    );
  }

  /// Card background color: selected → hover → surface (priority order).
  Color _cardColor(bool isDark, Color primary) {
    if (widget.selected) {
      return primary.withValues(alpha: isDark ? 0.12 : 0.08);
    }
    if (_hovered) {
      return primary.withValues(alpha: isDark ? 0.06 : 0.04);
    }
    return isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;
  }

  /// Card border color: selected/hover-interactive → primary, else base.
  Color _cardBorder(Color primary, Color baseBorder, bool isInteractive) {
    if (widget.selected) return primary;
    if (_hovered && isInteractive) return primary;
    return baseBorder;
  }

  /// 36×44 format icon on left of card.
  Widget _buildIcon(Color primary) {
    return Container(
      width: 36,
      height: 44,
      decoration: BoxDecoration(
        color: primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        iconForFormat(widget.job.input.format),
        size: 22,
        color: primary,
      ),
    );
  }

  /// Info column: file name, size + pages, error message (if failed).
  Widget _buildInfo(Color ink, Color inkMuted, String? size) {
    final job = widget.job;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(job.fileName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: MarkitTypography.mono,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: ink,
            )),
        const SizedBox(height: 2),
        Text(
          [
            if (size != null) size,
            if (job.pageCount != null)
              '${job.pageCount} ${Strings.pagesLabel}',
          ].join('  ·  '),
          style: TextStyle(
            fontSize: 11,
            fontFeatures: MarkitTypography.tabularFigures,
            color: inkMuted,
          ),
        ),
        if (widget.showStatus && job.status == JobStatus.failed) ...[
          const SizedBox(height: 4),
          JobErrorView(job: job),
        ],
      ],
    );
  }

  /// Right side card actions: status chip + download/remove buttons (conditional).
  List<Widget> _buildActions() {
    return [
      if (widget.showStatus) ...[
        const SizedBox(width: MarkitSpacing.sm),
        _StatusChip(status: widget.job.status),
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
    ];
  }

  /// Progress section (shown when running/indeterminate): phase label,
  /// page metadata & animation bar.
  List<Widget> _buildProgress(Color inkMuted, Color hairline) {
    final job = widget.job;
    return [
      const SizedBox(height: MarkitSpacing.sm),
      // Phase label + progress metadata (page X of Y · %).
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
                fontFamily: MarkitTypography.mono,
                fontSize: 10,
                fontFeatures: MarkitTypography.tabularFigures,
                color: inkMuted,
              ),
            ),
        ],
      ),
      const SizedBox(height: 3),
      // Smooth animation bar; indeterminate when total unknown.
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
                  builder: (context, value, _) => LinearProgressIndicator(
                    value: value,
                    minHeight: 5,
                    backgroundColor: hairline,
                  ),
                ),
        ),
      ),
    );
  }

  /// Progress metadata: "12 of 300 pages · 4%" (tabular figures).
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

/// Small status chip for file in batch.
class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final JobStatus status;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final (label, color) = switch (status) {
      JobStatus.queued => (
          Strings.fileQueued,
          isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight,
        ),
      JobStatus.running => (
          Strings.fileRunning,
          Theme.of(context).colorScheme.primary,
        ),
      JobStatus.done => (
          Strings.fileDone,
          isDark ? MarkitColors.stampGreenDark : MarkitColors.stampGreenLight,
        ),
      JobStatus.failed => (
          Strings.fileFailed,
          isDark ? MarkitColors.stampRedDark : MarkitColors.stampRedLight,
        ),
      JobStatus.cancelled => (
          Strings.fileCancelled,
          isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: MarkitSpacing.sm,
        vertical: MarkitSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(MarkitSpacing.radiusChip),
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
