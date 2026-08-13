import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/ui/frame_coalescer.dart';
import 'package:markit/ui/screens/about_screen.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/widgets/header/app_header.dart';
import 'package:markit/ui/widgets/header/status_pill.dart';
import 'package:markit/ui/widgets/document_viewer.dart';
import 'package:markit/ui/widgets/left_panel.dart';
import 'package:markit/ui/widgets/drop_zone.dart';
import 'package:markit/ui/download_text.dart';

import '../../core/output_mover.dart';
import '../../isolate/conversion_controller.dart';
import '../../theme/theme_controller.dart';

/// Main screen — two-panel desktop layout:
/// left = workspace (upload/queue/status/actions), right = document viewer.
/// Responsive: < 900px panels stack.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.controller,
    this.themeController,
  });

  final ConversionController controller;
  final ThemeController? themeController;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DateTime? _startTime;
  Timer? _ticker;
  String? _selectedJobId;
  late final ThemeController _theme =
      widget.themeController ?? ThemeController();
  // Coalesced rebuilds: high-frequency controller notifications
  // trigger at most one setState per frame.
  late final FrameCoalescer _rebuilds =
      FrameCoalescer(onFrame: _flushControllerChanged);

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_rebuilds.schedule);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_rebuilds.schedule);
    _rebuilds.dispose();
    _ticker?.cancel();
    super.dispose();
  }

  Future<void> _convertAll() async {
    final controller = widget.controller;
    if (controller.queue.isEmpty) return;

    _startConversion();
    var convertFailed = false;
    try {
      await controller.convertAll();
    } catch (_) {
      // convertAll should not throw (per-job failure handled by controller),
      // but if it occurs: proceed to save.
      convertFailed = true;
    } finally {
      // If convertAll throws, save is STILL offered — successful jobs
      // can be saved independently even if batch ends abnormally.
      if (!kIsWeb && mounted && convertFailed) {
        await _offerMoveOutputs(controller);
        // Discard unselected temp files.
        await controller.cleanupTempOutputs();
      }
    }
  }

  /// Save button in sidebar → choose destination folder for .md outputs (desktop).
  Future<void> _onSaveOutput() async {
    if (!mounted) return;
    final controller = widget.controller;
    await _offerMoveOutputs(controller);
    // Completed (saved or cancelled): unselected temp files discarded.
    await controller.cleanupTempOutputs();
  }

  /// Offer moving successful .md outputs to user-selected folder.
  /// Cancel dialog → temp files discarded (not saved automatically).
  Future<void> _offerMoveOutputs(ConversionController controller) async {
    final done = await _doneJobsWithOutput(controller);
    if (done.isEmpty || !mounted) return;

    final directory = await _pickOutputDirectory();
    if (directory == null || !mounted) {
      if (mounted) _showMoveSnack(0, null);
      return;
    }

    final plan = planOutputMoves([
      for (final job in done) (job.outputPath, job.input.outputName),
    ], directory);

    final overwrite = await _resolveMoveOverwrite(plan);
    if (!mounted) return;

    final applied = await applyOutputMoves(plan, overwrite: overwrite);
    final movedByFrom = {for (final (from, to) in applied) from: to};
    for (final job in done) {
      final target = movedByFrom[job.outputPath];
      if (target != null) job.outputPath = target;
    }
    if (!mounted) return;
    _showMoveSnack(applied.length, directory);
  }

  /// Open folder picker dialog. If plugin fails (e.g. test environment),
  /// treat same as cancel.
  Future<String?> _pickOutputDirectory() async {
    try {
      return await getDirectoryPath(
          confirmButtonText: Strings.chooseOutputFolder);
    } catch (_) {
      return null;
    }
  }

  /// Decide overwrite when target conflict exists in destination folder.
  Future<bool> _resolveMoveOverwrite(OutputMovePlan plan) async {
    if (!plan.hasConflicts || !mounted) return false;
    return _confirmMoveOverwrite(plan.conflicts.length);
  }

  /// SnackBar showing move results (or "not saved" info).
  void _showMoveSnack(int movedCount, String? directory) {
    final message = movedCount == 0 || directory == null
        ? Strings.outputNotSaved
        : Strings.outputSavedTo
            .replaceFirst('%d', '$movedCount')
            .replaceFirst('%s', directory);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Completed jobs whose output file exists (temp batch) — failed jobs
  /// or cleaned up files excluded.
  Future<List<QueuedFile>> _doneJobsWithOutput(
    ConversionController controller,
  ) async {
    final done = <QueuedFile>[];
    for (final job in controller.queue) {
      if (job.status != JobStatus.done) continue;
      if (await File(job.outputPath).exists()) done.add(job);
    }
    return done;
  }

  /// Overwrite confirmation dialog for destination targets.
  Future<bool> _confirmMoveOverwrite(int count) async {
    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text(Strings.overwriteTitle),
        content: Text(Strings.moveConflictsBody.replaceFirst('%d', '$count')),
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
    return proceed == true;
  }

  /// Start UI refresh ticker + record conversion start time.
  void _startConversion() {
    _startTime = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) _rebuilds.schedule();
    });
  }

  void _reset() {
    _ticker?.cancel();
    _selectedJobId = null;
    widget.controller.reset();
  }

  void _openAbout() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const AboutScreen()),
    );
  }

  Future<void> _addMoreFiles() async {
    final inputs = await pickPdfFiles();
    if (inputs.isEmpty) return;
    widget.controller.addFiles(inputs);
  }

  /// Flush coalesced controller changes: at most once per frame.
  void _flushControllerChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.controller.isRunning) {
        _ticker?.cancel();
      }
      // Auto-select first done document if none selected.
      final queue = widget.controller.queue;
      if (_selectedJobId == null) {
        final firstDone = queue.where((f) => f.status == JobStatus.done);
        if (firstDone.isNotEmpty) {
          _selectedJobId = firstDone.first.id;
        }
      } else {
        final stillExists = queue.any((f) => f.id == _selectedJobId);
        if (!stillExists) _selectedJobId = null;
      }
    });
  }

  QueuedFile? get _selectedJob {
    final queue = widget.controller.queue;
    if (_selectedJobId == null) return null;
    for (final job in queue) {
      if (job.id == _selectedJobId) return job;
    }
    return null;
  }

  double? get _progressFraction {
    final c = widget.controller;
    final running = c.queue.where((f) => f.status == JobStatus.running);
    if (running.isEmpty) return null;
    // Aggregate: average progress of running jobs.
    final fractions = running
        .map((j) => j.progressFraction)
        .whereType<double>()
        .toList();
    if (fractions.isEmpty) return null;
    return fractions.reduce((a, b) => a + b) / fractions.length;
  }

  String? get _runningInfo {
    final c = widget.controller;
    if (!c.isRunning) return null;
    final done = c.doneCount;
    final running = c.queue.where((f) => f.status == JobStatus.running).length;
    final elapsed = _startTime == null
        ? Duration.zero
        : DateTime.now().difference(_startTime!);
    final pct = _progressFraction == null
        ? ''
        : ' · ${((_progressFraction ?? 0) * 100).clamp(0, 100).toStringAsFixed(0)}%';
    return '$done/${c.queue.length} done · $running processing$pct'
        ' · ${_fmt(elapsed)}';
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = d.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _onDownloadFile(QueuedFile job) {
    final content = job.content;
    if (content == null) return;
    downloadTextFile(job.input.outputName, content);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(Strings.downloadStarted)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;

    return Scaffold(
      body: Stack(
        children: [
          Column(
            children: [
              AppHeader(
                onReset: !c.isRunning ? _reset : () {},
                onAbout: _openAbout,
                resetEnabled: !c.isRunning,
                themeController: _theme,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 900;
                    final leftPanel = LeftPanel(
                      controller: c,
                      onAddMore: _addMoreFiles,
                      onConvertAll: _convertAll,
                      onSaveOutput: _onSaveOutput,
                      onClear: _reset,
                      onRemove: c.removeFile,
                      onSelect: (job) =>
                          setState(() => _selectedJobId = job.id),
                      onDownloadFile: _onDownloadFile,
                      selectedJobId: _selectedJobId,
                      isRunning: c.isRunning,
                      progressFraction: _progressFraction,
                      runningInfo: _runningInfo,
                    );
                    final viewer = DocumentViewer(
                      job: _selectedJob,
                      onAddFiles: _addMoreFiles,
                    );

                    if (wide) {
                      // Wide layout: left viewer + right sidebar
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: viewer),
                          SizedBox(width: 320, child: sidebarPanel(leftPanel)),
                        ],
                      );
                    }
                    // Narrow screen: top viewer + bottom sidebar
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(child: viewer),
                        SizedBox(
                          height: constraints.maxHeight * 0.42,
                          child: sidebarPanel(leftPanel),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
          // Floating status pill in bottom-left corner.
          Positioned(
            left: MarkitSpacing.lg,
            bottom: MarkitSpacing.lg,
            child: StatusPill(controller: c),
          ),
        ],
      ),
    );
  }

  /// Sidebar utility panel: subtle left border + soft shadow.
  Widget sidebarPanel(Widget child) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: hairline)),
        boxShadow: [
          BoxShadow(
            color: (isDark ? MarkitColors.inkDark : MarkitColors.inkLight)
                .withValues(alpha: isDark ? 0.10 : 0.04),
            blurRadius: 10,
            offset: const Offset(-2, 0),
          ),
        ],
      ),
      child: child,
    );
  }
}
