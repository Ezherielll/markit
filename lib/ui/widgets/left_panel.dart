import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/ui/download_zip.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';
import 'package:markit/ui/widgets/drop_zone.dart';
import 'package:markit/ui/widgets/file_card.dart';

/// Left panel — workspace workflow: upload, file list, conversion status,
/// actions (Download ZIP primary / Add files secondary / Clear all danger).
class LeftPanel extends StatelessWidget {
  const LeftPanel({
    super.key,
    required this.controller,
    required this.onAddMore,
    required this.onConvertAll,
    required this.onClear,
    required this.onRemove,
    required this.onSelect,
    required this.onDownloadFile,
    required this.onSaveOutput,
    this.selectedJobId,
    this.isRunning = false,
    this.progressFraction,
    this.runningInfo,
  });

  final ConversionController controller;
  final VoidCallback onAddMore;
  final VoidCallback onConvertAll;
  final VoidCallback onClear;
  final void Function(String id) onRemove;
  final void Function(QueuedFile) onSelect;
  final void Function(QueuedFile) onDownloadFile;
  final VoidCallback onSaveOutput;
  final String? selectedJobId;
  final bool isRunning;
  final double? progressFraction;

  /// Status line info while running (e.g. "2 of 3 · 45% · 0:12").
  final String? runningInfo;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    final done = controller.doneCount;
    final isEmpty = queue.isEmpty;
    final warning = _largeBatchWarning(queue);

    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? MarkitColors.surfaceDark
          : MarkitColors.surfaceLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(context, queue, isEmpty),
          const Divider(height: 1),
          _buildContent(context, queue, done, warning),
        ],
      ),
    );
  }

  /// Panel header: title (changes when empty) + file count badge +
  /// add button (disabled while converting).
  Widget _buildHeader(
    BuildContext context,
    List<QueuedFile> queue,
    bool isEmpty,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        MarkitSpacing.lg,
        MarkitSpacing.lg,
        MarkitSpacing.sm,
        MarkitSpacing.sm,
      ),
      child: Row(
        children: [
          Text(
            isEmpty ? Strings.sidebarTitle : Strings.sidebarFiles,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (!isEmpty) ...[
            const SizedBox(width: MarkitSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 7,
                vertical: 1,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${queue.length}',
                style: TextStyle(
                  fontFamily: MarkitTypography.mono,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFeatures: MarkitTypography.tabularFigures,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          ],
          const Spacer(),
          IconButton(
            onPressed: isRunning ? null : onAddMore,
            icon: const Icon(Icons.add, size: 19),
            tooltip: Strings.addFiles,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// Scrollable content: drop zone (empty) or file list + bottom actions.
  Widget _buildContent(
    BuildContext context,
    List<QueuedFile> queue,
    int done,
    String? warning,
  ) {
    final isEmpty = queue.isEmpty;
    return Expanded(
      child: isEmpty
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(MarkitSpacing.lg),
              child: DropZone(
                compact: true,
                onFilesPicked: (inputs) {
                  controller.addFiles(inputs);
                },
              ),
            )
          // ListView.builder: only visible items constructed —
          // large batches do not construct all cards per rebuild.
          : ListView.builder(
              padding: const EdgeInsets.all(MarkitSpacing.md),
              itemCount: (warning != null ? 1 : 0) + queue.length + 1,
              itemBuilder: (context, index) =>
                  _buildQueueTile(context, index, queue, done, warning),
            ),
    );
  }

  /// Single list item row: warning banner, file card, or action footer.
  Widget _buildQueueTile(
    BuildContext context,
    int index,
    List<QueuedFile> queue,
    int done,
    String? warning,
  ) {
    final bannerOffset = warning != null ? 1 : 0;
    if (warning != null && index == 0) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WarningBanner(message: warning),
          const SizedBox(height: MarkitSpacing.md),
        ],
      );
    }
    if (index == bannerOffset + queue.length) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: MarkitSpacing.md),
          _buildActions(context, queue, done),
        ],
      );
    }
    final isLast = index == bannerOffset + queue.length - 1;
    return RepaintBoundary(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: isLast ? 0 : MarkitSpacing.sm,
        ),
        child: _buildCard(queue[index - bannerOffset]),
      ),
    );
  }

  /// Large batch warning (>10 files or file >100 pages).
  String? _largeBatchWarning(List<QueuedFile> queue) {
    if (queue.length > 10) {
      return Strings.warnLargeBatch.replaceFirst('%d', '${queue.length}');
    }
    for (final job in queue) {
      final pages = job.pageCount ?? job.totalPages;
      if (pages != null && pages > 100) {
        return Strings.warnLargePages
            .replaceFirst('%s', job.fileName)
            .replaceFirst('%d', '$pages');
      }
    }
    return null;
  }

  Widget _buildCard(QueuedFile job) {
    final isActive = job.status == JobStatus.running && isRunning;
    final canDownload = kIsWeb &&
        job.status == JobStatus.done &&
        job.content != null;
    return FileCard(
      job: job,
      showStatus: true,
      selected: job.id == selectedJobId,
      onTap: job.status == JobStatus.done ? () => onSelect(job) : null,
      onDownload: canDownload ? () => onDownloadFile(job) : null,
      onRemove: isRunning ? null : () => onRemove(job.id),
      // Per-job progress (concurrent): each card has its own progress.
      progress: isActive ? job.progressFraction : null,
      phase: controller.phase,
    );
  }

  Widget _buildActions(BuildContext context, List<QueuedFile> queue, int done) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (isRunning && runningInfo != null) ...[
          Row(
            children: [
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progressFraction,
                ),
              ),
              const SizedBox(width: MarkitSpacing.sm),
              Expanded(
                child: Text(
                  runningInfo!,
                  style: TextStyle(
                    fontFamily: MarkitTypography.mono,
                    fontSize: 11.5,
                    fontFeatures: MarkitTypography.tabularFigures,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? MarkitColors.inkMutedDark
                        : MarkitColors.inkMutedLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: MarkitSpacing.md),
        ],
        if (kIsWeb && done > 1) ...[
          FilledButton.icon(
            onPressed: () => _downloadAllZip(queue, done),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: Text('${Strings.downloadAllZip} ($done)'),
          ),
          const SizedBox(height: MarkitSpacing.sm),
        ],
        // Desktop: save .md outputs to chosen folder — shown when idle and
        // successful outputs exist (done > 0).
        if (!kIsWeb && !isRunning && done > 0) ...[
          FilledButton.icon(
            onPressed: onSaveOutput,
            icon: const Icon(Icons.folder_outlined, size: 18),
            label: Text('${Strings.saveOutput} ($done)'),
          ),
          const SizedBox(height: MarkitSpacing.sm),
        ],
        if (!isRunning &&
            queue.any((j) => j.status == JobStatus.queued))
          FilledButton.icon(
            onPressed: onConvertAll,
            icon: const Icon(Icons.auto_awesome, size: 18),
            label: Text(
              '${Strings.convertAllShort} (${queue.length})',
            ),
          ),
        if (isRunning)
          FilledButton.icon(
            onPressed: controller.cancel,
            icon: const Icon(Icons.stop, size: 18),
            label: const Text(Strings.cancel),
          ),
        const SizedBox(height: MarkitSpacing.sm),
        OutlinedButton.icon(
          onPressed: isRunning ? null : onAddMore,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(Strings.addFiles),
        ),
        const SizedBox(height: MarkitSpacing.xs),
        TextButton(
          onPressed: isRunning ? null : onClear,
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text(Strings.clearAll),
        ),
      ],
    );
  }
}

/// Large batch warning banner — inline, non-blocking.
class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final warn = isDark ? MarkitColors.stampRedDark : MarkitColors.stampRedLight;
    return Container(
      padding: const EdgeInsets.all(MarkitSpacing.md),
      decoration: BoxDecoration(
        color: warn.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
        border: Border.all(color: warn.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: warn),
          const SizedBox(width: MarkitSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: warn,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Collect all successful outputs (web) → download as a single ZIP.
void _downloadAllZip(List<QueuedFile> queue, int done) {
  final files = <String, String>{};
  for (final job in queue) {
    if (job.status == JobStatus.done && job.content != null) {
      files[job.input.outputName] = job.content!;
    }
  }
  if (files.isEmpty) return;
  downloadZipFile('markit-converted.zip', files);
}
