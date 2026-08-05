import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/widgets/app_header.dart';
import 'package:pdflow/ui/widgets/drop_zone.dart';
import 'package:pdflow/ui/widgets/file_card.dart';
import 'package:pdflow/ui/widgets/progress_panel.dart';

import '../../isolate/conversion_controller.dart';

/// Layar utama — state machine batch:
/// empty → queue → running → summary.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final ConversionController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _startTime;
  Timer? _ticker;
  bool _overwriteConfirmed = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    _ticker?.cancel();
    super.dispose();
  }

  void _onFilesPicked(List<String> paths) {
    widget.controller.addFiles(paths);
  }

  Future<void> _convertAll() async {
    final controller = widget.controller;
    if (controller.queue.isEmpty) return;

    // Konfirmasi overwrite sekali per batch (FR-12).
    if (!_overwriteConfirmed) {
      final conflicts = <String>[];
      for (final job in controller.queue) {
        if (await File(job.outputPath).exists()) {
          conflicts.add(job.outputPath);
        }
      }
      if (conflicts.isNotEmpty && mounted) {
        final proceed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text(Strings.overwriteTitle),
            content: Text(Strings.overwriteBody
                .replaceFirst('%d', '${conflicts.length}')),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text(Strings.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text(Strings.overwriteConfirm),
              ),
            ],
          ),
        );
        if (proceed != true || !mounted) return;
      }
      _overwriteConfirmed = true;
    }

    _startTime = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
    await controller.convertAll();
  }

  void _reset() {
    _ticker?.cancel();
    _overwriteConfirmed = false;
    widget.controller.reset();
  }

  Future<void> _addMoreFiles() async {
    final paths = await pickPdfFiles();
    if (paths.isEmpty) return;
    widget.controller.addFiles(paths);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.controller.isRunning) {
        _ticker?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            onReset: !c.isRunning ? _reset : () {},
            resetEnabled: !c.isRunning,
          ),
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: PdflowSpacing.xl,
                    vertical: PdflowSpacing.lg,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.03),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _buildBody(c),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(ConversionController c) {
    if (c.isRunning) {
      return _RunningState(
        key: const ValueKey('running'),
        controller: c,
        elapsed: _startTime == null
            ? Duration.zero
            : DateTime.now().difference(_startTime!),
        onCancel: c.cancel,
      );
    }

    // Summary: semua job berstatus final (done/failed/cancelled) & queue tidak kosong.
    final allFinal = c.queue.isNotEmpty &&
        c.queue.every((f) => f.status != JobStatus.queued);
    if (allFinal) {
      return _SummaryState(
        key: const ValueKey('summary'),
        controller: c,
        onAddMore: _addMoreFiles,
        onClear: _reset,
      );
    }

    if (c.queue.isEmpty) {
      return _EmptyState(
        key: const ValueKey('empty'),
        onFilesPicked: _onFilesPicked,
      );
    }

    // Queue menunggu konversi.
    return _QueueState(
      key: const ValueKey('queue'),
      controller: c,
      onAddMore: _addMoreFiles,
      onConvertAll: _convertAll,
      onRemove: c.removeFile,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.onFilesPicked});

  final ValueChanged<List<String>> onFilesPicked;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropZone(onFilesPicked: onFilesPicked),
          const SizedBox(height: PdflowSpacing.xxl),
          const _FeatureRow(),
        ],
      ),
    );
  }
}

class _QueueState extends StatelessWidget {
  const _QueueState({
    super.key,
    required this.controller,
    required this.onAddMore,
    required this.onConvertAll,
    required this.onRemove,
  });

  final ConversionController controller;
  final VoidCallback onAddMore;
  final VoidCallback onConvertAll;
  final void Function(String id) onRemove;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${queue.length} ${queue.length == 1 ? Strings.pickFileSingular : 'files'}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: PdflowSpacing.lg),
          for (var i = 0; i < queue.length; i++) ...[
            FileCard(
              job: queue[i],
              showStatus: true,
              onRemove: () => onRemove(queue[i].id),
            ),
            if (i < queue.length - 1) const SizedBox(height: PdflowSpacing.sm),
          ],
          const SizedBox(height: PdflowSpacing.xl),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onConvertAll,
                  icon: const Icon(Icons.auto_awesome, size: 18),
                  label: Text(
                    '${Strings.convertAll} (${queue.length})',
                  ),
                ),
              ),
              const SizedBox(width: PdflowSpacing.sm),
              IconButton(
                onPressed: onAddMore,
                icon: const Icon(Icons.add),
                tooltip: Strings.addFiles,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RunningState extends StatelessWidget {
  const _RunningState({
    super.key,
    required this.controller,
    required this.elapsed,
    required this.onCancel,
  });

  final ConversionController controller;
  final Duration elapsed;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    final active = controller.activeJob;
    final done = controller.doneCount;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${done + 1} of ${queue.length}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: PdflowSpacing.md),
          ProgressPanel(
            currentPage: controller.currentPage ?? 0,
            totalPages: controller.totalPages ?? 0,
            elapsed: elapsed,
            onCancel: onCancel,
            passTwo: controller.phase == 1 && (controller.currentPage ?? 0) > 0,
          ),
          if (active != null) ...[
            const SizedBox(height: PdflowSpacing.lg),
            FileCard(job: active, showStatus: true),
          ],
          const SizedBox(height: PdflowSpacing.lg),
          for (final job in queue)
            if (job.status != JobStatus.queued) ...[
              FileCard(job: job, showStatus: true),
              const SizedBox(height: PdflowSpacing.sm),
            ],
        ],
      ),
    );
  }
}

class _SummaryState extends StatelessWidget {
  const _SummaryState({
    super.key,
    required this.controller,
    required this.onAddMore,
    required this.onClear,
  });

  final ConversionController controller;
  final VoidCallback onAddMore;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final queue = controller.queue;
    final done = controller.doneCount;
    final failed = queue.where((f) => f.status == JobStatus.failed).length;

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                failed > 0 ? Icons.warning_amber : Icons.check_circle,
                color: failed > 0
                    ? Theme.of(context).colorScheme.error
                    : (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF7FB590)
                        : const Color(0xFF3D6B4F)),
              ),
              const SizedBox(width: PdflowSpacing.sm),
              Text(
                failed > 0
                    ? '$done converted, $failed failed'
                    : Strings.filesDone.replaceFirst('%d', '$done')
                        .replaceFirst('%d', '${queue.length}'),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ],
          ),
          const SizedBox(height: PdflowSpacing.lg),
          for (var i = 0; i < queue.length; i++) ...[
            FileCard(
              job: queue[i],
              showStatus: true,
            ),
            if (i < queue.length - 1) const SizedBox(height: PdflowSpacing.sm),
          ],
          const SizedBox(height: PdflowSpacing.xl),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onAddMore,
                  icon: const Icon(Icons.add),
                  label: const Text(Strings.addFiles),
                ),
              ),
              const SizedBox(width: PdflowSpacing.sm),
              OutlinedButton(
                onPressed: onClear,
                child: const Text(Strings.clearAll),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tiga poin fitur kecil di bawah drop zone.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow();

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.bolt, Strings.featureFast, Strings.featureFastSub),
      (Icons.lock_outline, Strings.featureOffline, Strings.featureOfflineSub),
      (Icons.article_outlined, Strings.featureClean, Strings.featureCleanSub),
    ];
    return Wrap(
      spacing: PdflowSpacing.xl,
      runSpacing: PdflowSpacing.lg,
      alignment: WrapAlignment.center,
      children: [
        for (final (icon, title, sub) in items)
          SizedBox(
            width: 200,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: PdflowSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: Theme.of(context).textTheme.labelMedium),
                      const SizedBox(height: 2),
                      Text(sub, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
