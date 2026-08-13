import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
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

    _startConversion();
    var convertFailed = false;
    try {
      await controller.convertAll();
    } catch (_) {
      // convertAll tidak seharusnya throw (per-job failure ditangani
      // controller), tapi bila terjadi: tetap lanjut ke save.
      convertFailed = true;
    } finally {
      // Bila convertAll melempar, save TETAP ditawarkan — job yang sukses
      // bisa disimpan independen walau batch tidak selesai normal.
      // (Batch normal memakai tombol Save di sidebar — auto-dialog sudah
      // diganti tombol; di sini finally adalah jalur penyelamat.)
      if (!kIsWeb && mounted && convertFailed) {
        await _offerMoveOutputs(controller);
        // File yang tidak sempat disimpan user dibuang dari temp.
        await controller.cleanupTempOutputs();
      }
    }
  }

  /// Tombol Save di sidebar → pilih folder tujuan hasil .md (desktop).
  Future<void> _onSaveOutput() async {
    if (!mounted) return;
    final controller = widget.controller;
    await _offerMoveOutputs(controller);
    // Selesai (disimpan atau dibatalkan): file temp yang tidak terpilih
    // dibuang — tidak ada yang "tersimpan otomatis".
    await controller.cleanupTempOutputs();
  }

  /// Tawarkan pemindahan output .md yang sukses ke folder pilihan user.
  /// Cancel dialog → file temp dibuang (tidak tersimpan otomatis).
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

  /// Buka dialog pilih folder. Bila plugin gagal (mis. lingkungan test tanpa
  /// implementasi channel), perlakukan sama seperti cancel.
  Future<String?> _pickOutputDirectory() async {
    try {
      return await getDirectoryPath(
          confirmButtonText: Strings.chooseOutputFolder);
    } catch (_) {
      return null;
    }
  }

  /// Putuskan overwrite bila ada konflik target di folder tujuan.
  Future<bool> _resolveMoveOverwrite(OutputMovePlan plan) async {
    if (!plan.hasConflicts || !mounted) return false;
    return _confirmMoveOverwrite(plan.conflicts.length);
  }

  /// SnackBar hasil pemindahan (atau info "tidak disimpan").
  void _showMoveSnack(int movedCount, String? directory) {
    final message = movedCount == 0 || directory == null
        ? Strings.outputNotSaved
        : Strings.outputSavedTo
            .replaceFirst('%d', '$movedCount')
            .replaceFirst('%s', directory);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  /// Job done yang file-nya benar-benar ada (temp batch) — job failed atau
  /// file yang sudah dibersihkan tidak ikut.
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

  /// Dialog konfirmasi overwrite untuk target di folder tujuan (fase Save;
  /// konflik di direktori pilihan user — pola dialog konfirmasi standar).
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

  /// Mulai ticker refresh UI + catat waktu mulai konversi.
  void _startConversion() {
    _startTime = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
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
    final running = c.queue.where((f) => f.status == JobStatus.running);
    if (running.isEmpty) return null;
    // Agregat: rata-rata progress job running (per-job progress di kartu).
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
