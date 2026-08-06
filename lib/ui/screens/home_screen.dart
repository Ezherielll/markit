import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/widgets/header/app_header.dart';
import 'package:pdflow/ui/widgets/header/status_pill.dart';
import 'package:pdflow/ui/widgets/document_viewer.dart';
import 'package:pdflow/ui/widgets/left_panel.dart';
import 'package:pdflow/ui/widgets/drop_zone.dart';
import 'package:pdflow/ui/download_text.dart';

import '../../isolate/conversion_controller.dart';
import '../../theme/theme_controller.dart';

/// Layar utama — layout desktop dua panel:
/// kiri = workspace (upload/queue/status/aksi), kanan = document viewer.
/// Responsive: < 900px panel menumpuk.
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
  bool _overwriteConfirmed = false;
  String? _selectedJobId;
  late final ThemeController _theme =
      widget.themeController ?? ThemeController();

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

  Future<void> _convertAll() async {
    final controller = widget.controller;
    if (controller.queue.isEmpty) return;

    // Konfirmasi overwrite sekali per batch (FR-12) — hanya desktop;
    // di web output selalu di memory (tidak ada filesystem).
    if (!kIsWeb && !_overwriteConfirmed) {
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
    _selectedJobId = null;
    widget.controller.reset();
  }

  Future<void> _addMoreFiles() async {
    final inputs = await pickPdfFiles();
    if (inputs.isEmpty) return;
    widget.controller.addFiles(inputs);
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      if (!widget.controller.isRunning) {
        _ticker?.cancel();
      }
      // Auto-select dokumen done pertama bila belum ada pilihan.
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
    final total = c.totalPages ?? 0;
    final page = c.currentPage ?? 0;
    if (total <= 0) return null;
    return page / total;
  }

  String? get _runningInfo {
    final c = widget.controller;
    if (!c.isRunning) return null;
    final done = c.doneCount;
    final page = c.currentPage ?? 0;
    final total = c.totalPages ?? 0;
    final elapsed = _startTime == null
        ? Duration.zero
        : DateTime.now().difference(_startTime!);
    final pct = _progressFraction == null
        ? ''
        : ' · ${((_progressFraction ?? 0) * 100).clamp(0, 100).toStringAsFixed(0)}%';
    return '${done + 1}/${c.queue.length} · $page/$total$pct'
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
                      // Workspace kiri (dominant, ~75%) + sidebar kanan
                      // (panel utilitas ~25%) — reading flow kiri→kanan.
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(flex: 3, child: viewer),
                          SizedBox(width: 320, child: sidebarPanel(leftPanel)),
                        ],
                      );
                    }
                    // Layar sempit: workspace atas (dominant), sidebar bawah
                    // sebagai drawer utilitas yang tetap mengalir.
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
          // Status pill floating di sudut kiri bawah.
          Positioned(
            left: PdflowSpacing.lg,
            bottom: PdflowSpacing.lg,
            child: StatusPill(controller: c),
          ),
        ],
      ),
    );
  }

  /// Sidebar sebagai panel utilitas: border kiri halus + shadow lembut,
  /// bukan divider keras — terasa attached, bukan halaman terpisah.
  Widget sidebarPanel(Widget child) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: hairline)),
        boxShadow: [
          BoxShadow(
            color: (isDark ? PdflowColors.inkDark : PdflowColors.inkLight)
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
