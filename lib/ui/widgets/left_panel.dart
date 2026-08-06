import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/isolate/conversion_controller.dart';
import 'package:pdflow/ui/download_zip.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';
import 'package:pdflow/ui/widgets/drop_zone.dart';
import 'package:pdflow/ui/widgets/file_card.dart';

/// Panel kiri — semua alur kerja: upload, daftar file, status konversi,
/// aksi (Download ZIP primary / Add files secondary / Clear all danger).
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
  final String? selectedJobId;
  final bool isRunning;
  final double? progressFraction;

  /// Info baris status saat running (mis. "2 of 3 · 45% · 0:12").
  final String? runningInfo;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    final done = controller.doneCount;
    final isEmpty = queue.isEmpty;

    return Container(
      color: Theme.of(context).brightness == Brightness.dark
          ? PdflowColors.surfaceDark
          : PdflowColors.surfaceLight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header panel.
          Padding(
            padding: const EdgeInsets.fromLTRB(
              PdflowSpacing.lg,
              PdflowSpacing.lg,
              PdflowSpacing.sm,
              PdflowSpacing.sm,
            ),
            child: Row(
              children: [
                Text(
                  isEmpty ? Strings.sidebarTitle : Strings.sidebarFiles,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (!isEmpty) ...[
                  const SizedBox(width: PdflowSpacing.sm),
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
                        fontFamily: PdflowTypography.mono,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        fontFeatures: PdflowTypography.tabularFigures,
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
          ),
          const Divider(height: 1),
          // Isi scrollable: drop zone (kosong) / daftar file + aksi bawah.
          Expanded(
            child: isEmpty
                ? SingleChildScrollView(
                    padding: const EdgeInsets.all(PdflowSpacing.lg),
                    child: DropZone(
                      compact: true,
                      onFilesPicked: (inputs) {
                        controller.addFiles(inputs);
                      },
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(PdflowSpacing.md),
                    children: [
                      for (var i = 0; i < queue.length; i++) ...[
                        _buildCard(queue[i]),
                        if (i < queue.length - 1)
                          const SizedBox(height: PdflowSpacing.sm),
                      ],
                      const SizedBox(height: PdflowSpacing.md),
                      _buildActions(context, queue, done),
                    ],
                  ),
          ),
        ],
      ),
    );
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
      progress: isActive ? progressFraction : null,
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
              const SizedBox(width: PdflowSpacing.sm),
              Expanded(
                child: Text(
                  runningInfo!,
                  style: TextStyle(
                    fontFamily: PdflowTypography.mono,
                    fontSize: 11.5,
                    fontFeatures: PdflowTypography.tabularFigures,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? PdflowColors.inkMutedDark
                        : PdflowColors.inkMutedLight,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: PdflowSpacing.md),
        ],
        if (kIsWeb && done > 1) ...[
          FilledButton.icon(
            onPressed: () => _downloadAllZip(queue, done),
            icon: const Icon(Icons.archive_outlined, size: 18),
            label: Text('${Strings.downloadAllZip} ($done)'),
          ),
          const SizedBox(height: PdflowSpacing.sm),
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
        const SizedBox(height: PdflowSpacing.sm),
        OutlinedButton.icon(
          onPressed: isRunning ? null : onAddMore,
          icon: const Icon(Icons.add, size: 18),
          label: const Text(Strings.addFiles),
        ),
        const SizedBox(height: PdflowSpacing.xs),
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

/// Kumpulkan semua output sukses (web) → unduh sebagai satu ZIP.
void _downloadAllZip(List<QueuedFile> queue, int done) {
  final files = <String, String>{};
  for (final job in queue) {
    if (job.status == JobStatus.done && job.content != null) {
      files[job.input.outputName] = job.content!;
    }
  }
  if (files.isEmpty) return;
  downloadZipFile('pdflow-converted.zip', files);
}
