import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';
import 'package:url_launcher/url_launcher.dart';

import '../download_text.dart';
import 'markdown_helpers.dart';

/// Panel kanan — workspace utama: document viewer (paper-like reading surface)
/// dengan toolbar sticky (rendered/raw toggle, download/open) + empty state.
/// Preview mendapat mayoritas ruang layar — fokus utama aplikasi.
class DocumentViewer extends StatefulWidget {
  const DocumentViewer({
    super.key,
    required this.job,
    this.onAddFiles,
  });

  /// Dokumen yang ditampilkan; null = empty state.
  final QueuedFile? job;

  /// Aksi empty state (tambahkan file).
  final VoidCallback? onAddFiles;

  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  static const int maxPreviewChars = 64 * 1024;

  String? _content;
  String? _preview;
  bool _previewTruncated = false;
  MdStats? _stats;
  bool _showRaw = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DocumentViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.job?.id != widget.job?.id) {
      _showRaw = false;
      _content = null;
      _preview = null;
      _stats = null;
      _load();
    }
  }

  Future<void> _load() async {
    final job = widget.job;
    if (job == null) return;

    String content;
    if (kIsWeb) {
      content = job.content ?? '';
    } else {
      final file = File(job.outputPath);
      if (!await file.exists()) return;
      content = await file.readAsString();
    }

    final truncated = truncateMarkdownPreview(
      content,
      maxChars: maxPreviewChars,
    );
    if (!mounted) return;
    setState(() {
      _content = content;
      _preview = truncated.preview;
      _previewTruncated = truncated.truncated;
      _stats = computeMdStats(content);
    });
  }

  Future<void> _openFolder() async {
    final job = widget.job;
    if (job == null) return;
    final dir = File(job.outputPath).parent.path;
    final ok = await launchUrl(Uri.file(dir));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open folder.')),
      );
    }
  }

  void _download() {
    final job = widget.job;
    final content = _content;
    if (job == null || content == null) return;
    downloadTextFile(job.input.outputName, content);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(Strings.downloadStarted)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = widget.job;
    if (job == null) {
      return _EmptyViewer(onAddFiles: widget.onAddFiles);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
    final stats = _stats;

    return Column(
      children: [
        // Toolbar sticky: nama file + metadata ringan + toggle + aksi.
        _ViewerToolbar(
          job: job,
          stats: stats,
          showRaw: _showRaw,
          onToggleRaw: (raw) => setState(() => _showRaw = raw),
          onDownload: _download,
          onOpenFolder: _openFolder,
        ),
        const Divider(height: 1),
        // Kertas dokumen.
        Expanded(
          child: RepaintBoundary(
            child: Container(
              color: isDark ? PdflowColors.paperDark : PdflowColors.paperLight,
              child: _content == null
                  ? const _PreviewSkeleton()
                  : SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: PdflowSpacing.xxxl,
                        vertical: PdflowSpacing.xxl,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 720),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_previewTruncated)
                                Padding(
                                  padding: const EdgeInsets.only(
                                    bottom: PdflowSpacing.md,
                                  ),
                                  child: Text(
                                    Strings.previewTruncated,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontStyle: FontStyle.italic,
                                      color: inkMuted,
                                    ),
                                  ),
                                ),
                              if (_showRaw)
                                // Raw view: baris utuh (no-wrap) + scroll
                                // horizontal; seleksi tetap tersedia (M4).
                                Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SelectionArea(
                                      child: Text(
                                        _preview!,
                                        softWrap: false,
                                        style: TextStyle(
                                          fontFamily: PdflowTypography.mono,
                                          fontSize: 12.5,
                                          height: 1.6,
                                          color: ink,
                                        ),
                                      ),
                                    ),
                                  ),
                                )
                              else
                                MarkdownBody(
                                  data: _preview!,
                                  styleSheet: documentMarkdownStyle(context),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Toolbar preview — metadata ringan (bukan menonjol), toggle, aksi.
class _ViewerToolbar extends StatelessWidget {
  const _ViewerToolbar({
    required this.job,
    required this.stats,
    required this.showRaw,
    required this.onToggleRaw,
    required this.onDownload,
    required this.onOpenFolder,
  });

  final QueuedFile job;
  final MdStats? stats;
  final bool showRaw;
  final ValueChanged<bool> onToggleRaw;
  final VoidCallback onDownload;
  final VoidCallback onOpenFolder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;

    final s = stats;
    final meta = [
      if (s != null) ...[
        if (s.headings > 0)
          '${s.headings} ${Strings.statsHeading.toLowerCase()} · ',
        if (s.paragraphs > 0)
          '${s.paragraphs} ${Strings.statsParagraphs.toLowerCase()} · ',
        if (s.listItems > 0)
          '${s.listItems} ${Strings.statsListItems.toLowerCase()} · ',
        if (s.tableRows > 0)
          '${s.tableRows} ${Strings.statsRows.toLowerCase()} · ',
      ],
    ].join();

    return Container(
      color: isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight,
      padding: const EdgeInsets.symmetric(
        horizontal: PdflowSpacing.lg,
        vertical: PdflowSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  job.input.outputName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: PdflowTypography.mono,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
                if (meta.isNotEmpty)
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PdflowTypography.ui,
                      fontSize: 11,
                      color: inkMuted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: PdflowSpacing.md),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text(Strings.showRendered)),
              ButtonSegment(value: true, label: Text(Strings.showRaw)),
            ],
            selected: {showRaw},
            onSelectionChanged: (s) => onToggleRaw(s.first),
            style: SegmentedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(
                fontFamily: PdflowTypography.ui,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: PdflowSpacing.sm),
          if (kIsWeb)
            IconButton(
              onPressed: onDownload,
              icon: const Icon(Icons.download_outlined, size: 19),
              tooltip: Strings.download,
            )
          else
            IconButton(
              onPressed: onOpenFolder,
              icon: const Icon(Icons.folder_open_outlined, size: 19),
              tooltip: Strings.openOutput,
            ),
        ],
      ),
    );
  }
}

/// Empty state viewer — komposisi, bukan blank space.
class _EmptyViewer extends StatelessWidget {
  const _EmptyViewer({this.onAddFiles});

  final VoidCallback? onAddFiles;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(PdflowSpacing.xl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.article_outlined,
                size: 56,
                color: isDark
                    ? PdflowColors.hairlineDark
                    : PdflowColors.hairlineLight,
              ),
              const SizedBox(height: PdflowSpacing.lg),
              Text(
                Strings.viewerEmptyTitle,
                style: Theme.of(context).textTheme.titleLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PdflowSpacing.sm),
              Text(
                Strings.viewerEmptySub,
                style: TextStyle(color: inkMuted),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: PdflowSpacing.xl),
              if (onAddFiles != null)
                FilledButton.icon(
                  onPressed: onAddFiles,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(Strings.addFiles),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton loading preview — bar abu-abu pulsing yang mencerminkan bentuk
/// dokumen markdown (heading + baris teks), bukan spinner generic.
class _PreviewSkeleton extends StatefulWidget {
  const _PreviewSkeleton();

  @override
  State<_PreviewSkeleton> createState() => _PreviewSkeletonState();
}

class _PreviewSkeletonState extends State<_PreviewSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark
        ? PdflowColors.hairlineDark.withValues(alpha: 0.6)
        : PdflowColors.hairlineLight;
    final highlight = isDark
        ? PdflowColors.surfaceRaisedDark
        : PdflowColors.surfaceRaisedLight;

    Widget bar(double width, double height) => FadeTransition(
          opacity: Tween(begin: 0.45, end: 1.0).animate(_controller),
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: base,
              borderRadius: BorderRadius.circular(3),
              gradient: LinearGradient(
                colors: [base, highlight, base],
              ),
            ),
          ),
        );

    return Center(
      child: SizedBox(
        width: 720,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            bar(180, 18),
            const SizedBox(height: PdflowSpacing.lg),
            bar(double.infinity, 10),
            const SizedBox(height: PdflowSpacing.sm),
            bar(double.infinity, 10),
            const SizedBox(height: PdflowSpacing.sm),
            bar(280, 10),
            const SizedBox(height: PdflowSpacing.lg),
            bar(120, 10),
            const SizedBox(height: PdflowSpacing.sm),
            bar(double.infinity, 10),
          ],
        ),
      ),
    );
  }
}
