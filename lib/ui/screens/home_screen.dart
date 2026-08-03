import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdflow/core/pdfrx_source.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/widgets/app_header.dart';
import 'package:pdflow/ui/widgets/drop_zone.dart';
import 'package:pdflow/ui/widgets/file_card.dart';
import 'package:pdflow/ui/widgets/progress_panel.dart';
import 'package:pdflow/ui/widgets/result_panel.dart';

import '../../isolate/conversion_controller.dart';

/// Layar utama — state machine: empty → selected → running → done/error.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.controller});

  final ConversionController controller;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _pdfPath;
  int? _pageCount;
  double? _bodyFontSize;
  String? _errorMessage;
  List<int> _failedPages = const [];
  DateTime? _startTime;
  Timer? _ticker;

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

  void _onFilePicked(String path) {
    setState(() {
      _pdfPath = path;
      _pageCount = null;
      _bodyFontSize = null;
      _errorMessage = null;
      _failedPages = const [];
    });
    _probe(path);
  }

  /// Estimasi halaman dari metadata (FR-01: < 2 s).
  Future<void> _probe(String path) async {
    try {
      final count = await PdfrxSource.probePageCount(path);
      if (mounted && _pdfPath == path) {
        setState(() => _pageCount = count);
      }
    } catch (_) {
      // Divalidasi saat convert; probe gagal tidak fatal.
    }
  }

  Future<void> _convert() async {
    final path = _pdfPath;
    if (path == null) return;

    final outPath = path.replaceFirst(
      RegExp(r'\.pdf$', caseSensitive: false),
      '.md',
    );

    // FR-12: konfirmasi overwrite bila file tujuan sudah ada.
    if (await File(outPath).exists() && mounted) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text(Strings.overwriteTitle),
          content: const Text(Strings.overwriteBody),
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

    _startTime = DateTime.now();
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (mounted) setState(() {});
    });
    await widget.controller.convert(pdfPath: path, outputPath: outPath);
  }

  void _reset() {
    _ticker?.cancel();
    widget.controller.reset();
    setState(() {
      _pdfPath = null;
      _pageCount = null;
      _bodyFontSize = null;
      _errorMessage = null;
      _failedPages = const [];
    });
  }

  void _onControllerChanged() {
    if (!mounted) return;
    final c = widget.controller;
    setState(() {
      if (c.errorType != null) {
        _errorMessage = switch (c.errorType) {
          'encrypted' => Strings.errorEncrypted,
          'noText' => Strings.errorNoText,
          'corrupt' => Strings.errorCorrupt,
          _ => c.errorMessage ??
              Strings.errorGeneric.replaceFirst('%s', c.errorMessage ?? ''),
        };
        _ticker?.cancel();
      } else if (c.outputPath != null) {
        _errorMessage = null;
        _failedPages = c.failedPages;
        _bodyFontSize = c.bodyFontSize;
        _ticker?.cancel();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final idle = !c.isRunning;

    return Scaffold(
      body: Column(
        children: [
          AppHeader(
            onReset: idle ? _reset : () {},
            resetEnabled: idle,
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

    if (c.errorType != null || _errorMessage != null) {
      return _DoneState(
        key: const ValueKey('error'),
        outputPath: null,
        errorMessage: _errorMessage,
        failedPages: const [],
        onReset: _reset,
      );
    }

    if (c.outputPath != null) {
      return _DoneState(
        key: const ValueKey('done'),
        outputPath: c.outputPath,
        errorMessage: null,
        failedPages: _failedPages,
        onReset: _reset,
      );
    }

    if (_pdfPath == null) {
      return _EmptyState(
        key: const ValueKey('empty'),
        onFilePicked: _onFilePicked,
      );
    }

    return _SelectedState(
      key: const ValueKey('selected'),
      path: _pdfPath!,
      pageCount: _pageCount,
      bodyFontSize: _bodyFontSize,
      onConvert: _convert,
      onReset: _reset,
      canConvert: _pageCount != null,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({super.key, required this.onFilePicked});

  final ValueChanged<String> onFilePicked;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropZone(onFilePicked: onFilePicked),
          const SizedBox(height: PdflowSpacing.xxl),
          const _FeatureRow(),
        ],
      ),
    );
  }
}

class _SelectedState extends StatelessWidget {
  const _SelectedState({
    super.key,
    required this.path,
    this.pageCount,
    this.bodyFontSize,
    required this.onConvert,
    required this.onReset,
    required this.canConvert,
  });

  final String path;
  final int? pageCount;
  final double? bodyFontSize;
  final VoidCallback onConvert;
  final VoidCallback onReset;
  final bool canConvert;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Ready to convert',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        const SizedBox(height: PdflowSpacing.sm),
        Text(
          'The PDF will be converted to Markdown in the same folder.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: PdflowSpacing.xl),
        FileCard(path: path, pageCount: pageCount, bodyFontSize: bodyFontSize),
        const SizedBox(height: PdflowSpacing.xl),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: canConvert ? onConvert : null,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text(Strings.convert),
              ),
            ),
            const SizedBox(width: PdflowSpacing.sm),
            IconButton(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              tooltip: Strings.reset,
            ),
          ],
        ),
      ],
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (controller.currentPage == null || controller.currentPage == 0) ...[
          Text(
            Strings.phaseReading,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: PdflowSpacing.xl),
        ],
        ProgressPanel(
          currentPage: controller.currentPage ?? 0,
          totalPages: controller.totalPages ?? 0,
          elapsed: elapsed,
          onCancel: onCancel,
          passTwo: controller.phase == 1 && (controller.currentPage ?? 0) > 0,
        ),
      ],
    );
  }
}

class _DoneState extends StatelessWidget {
  const _DoneState({
    super.key,
    this.outputPath,
    this.errorMessage,
    this.failedPages = const [],
    required this.onReset,
  });

  final String? outputPath;
  final String? errorMessage;
  final List<int> failedPages;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    if (outputPath != null) {
      return SingleChildScrollView(
        child: ResultPanel(
          outputPath: outputPath!,
          failedPages: failedPages,
          onReset: onReset,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.error_outline, size: 48),
        const SizedBox(height: PdflowSpacing.lg),
        Text(errorMessage ?? Strings.errorGeneric.replaceFirst('%s', '')),
        const SizedBox(height: PdflowSpacing.xl),
        FilledButton.icon(
          onPressed: onReset,
          icon: const Icon(Icons.folder_open),
          label: const Text(Strings.pickFile),
        ),
      ],
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
