import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/isolate/conversion_controller.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';
import 'package:pdflow/ui/widgets/stat_chip.dart';
import 'package:url_launcher/url_launcher.dart';

import '../download_text.dart';

/// Panel hasil (FR-09): preview markdown di-render seperti halaman kertas
/// (toggle Rendered/Raw), stat chips, aksi adaptif platform.
///
/// Desktop: konten dibaca dari file output; aksi = Open folder + Copy path.
/// Web: konten dari [QueuedFile.content] (memory); aksi = Download.
class ResultPanel extends StatefulWidget {
  const ResultPanel({super.key, required this.job, this.onReset});

  final QueuedFile job;
  final VoidCallback? onReset;

  @override
  State<ResultPanel> createState() => _ResultPanelState();
}

class _ResultPanelState extends State<ResultPanel> {
  String? _content;
  _MdStats? _stats;
  bool _showRaw = false;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    String content;
    if (kIsWeb) {
      content = widget.job.content ?? '';
    } else {
      final file = File(widget.job.outputPath);
      if (!await file.exists()) return;
      content = await file.readAsString();
    }

    // Stats struktur: hitung per baris dari konten.
    final stats = _MdStats();
    for (final line in const LineSplitter().convert(content)) {
      stats.countLine(line);
    }
    if (!mounted) return;
    setState(() {
      _content = content;
      _stats = stats;
    });
  }

  Future<void> _openFolder() async {
    final dir = File(widget.job.outputPath).parent.path;
    final ok = await launchUrl(Uri.file(dir));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open folder.')),
      );
    }
  }

  Future<void> _copyName() async {
    await Clipboard.setData(ClipboardData(text: widget.job.outputPath));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(Strings.copied)),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
  }

  void _download() {
    final content = _content;
    if (content == null) return;
    downloadTextFile(
      widget.job.input.outputName,
      content,
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(Strings.downloadStarted)),
    );
  }

  MarkdownStyleSheet _mdStyle(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
    final primary = Theme.of(context).colorScheme.primary;
    final base = MarkdownStyleSheet.fromTheme(Theme.of(context));

    return base.copyWith(
      h1: TextStyle(
        fontFamily: PdflowTypography.display,
        fontSize: 22,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      h2: TextStyle(
        fontFamily: PdflowTypography.display,
        fontSize: 18,
        height: 1.25,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      h3: TextStyle(
        fontFamily: PdflowTypography.display,
        fontSize: 16,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
      p: TextStyle(fontSize: 14.5, height: 1.6, color: ink),
      listBullet: TextStyle(fontSize: 14.5, color: inkMuted),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: primary, width: 3)),
      ),
      code: TextStyle(
        fontFamily: PdflowTypography.mono,
        fontSize: 12.5,
        color: primary,
        backgroundColor: Colors.transparent,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(
            color: isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    final stats = _stats;
    final name = widget.job.input.outputName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.check_circle,
                color: isDark ? PdflowColors.stampGreenDark : PdflowColors.stampGreenLight),
            const SizedBox(width: PdflowSpacing.sm),
            Expanded(
              child: Text(
                name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: PdflowTypography.mono,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: ink,
                ),
              ),
            ),
          ],
        ),
        if (widget.job.failedPages.isNotEmpty) ...[
          const SizedBox(height: PdflowSpacing.sm),
          Text(
            Strings.warningFailedPages
                .replaceFirst('%d', '${widget.job.failedPages.length}'),
            style: TextStyle(
              fontSize: 12.5,
              color: isDark ? PdflowColors.stampRedDark : PdflowColors.stampRedLight,
            ),
          ),
        ],
        const SizedBox(height: PdflowSpacing.lg),
        Wrap(
          spacing: PdflowSpacing.sm,
          runSpacing: PdflowSpacing.sm,
          children: [
            if (stats != null) ...[
              StatChip(label: Strings.statsHeading, value: '${stats.headings}'),
              StatChip(label: Strings.statsParagraphs, value: '${stats.paragraphs}'),
              StatChip(label: Strings.statsListItems, value: '${stats.listItems}'),
            ],
            StatChip(label: Strings.statsTime, value: '—'),
          ],
        ),
        const SizedBox(height: PdflowSpacing.lg),
        Row(
          children: [
            Text(Strings.previewTitle,
                style: TextStyle(
                  fontFamily: PdflowTypography.display,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: ink,
                )),
            const Spacer(),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text(Strings.showRendered)),
                ButtonSegment(value: true, label: Text(Strings.showRaw)),
              ],
              selected: {_showRaw},
              onSelectionChanged: (s) => setState(() => _showRaw = s.first),
              style: SegmentedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                textStyle: const TextStyle(
                  fontFamily: PdflowTypography.ui,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: PdflowSpacing.md),
        // "Halaman kertas": preview dalam kartu putih dengan margin kertas.
        Container(
          height: 320,
          width: double.infinity,
          decoration: BoxDecoration(
            color: isDark ? PdflowColors.paperDark : PdflowColors.paperLight,
            borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
            border: Border.all(color: hairline),
          ),
          padding: const EdgeInsets.all(PdflowSpacing.xl),
          child: _content == null
              ? const Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                  child: _showRaw
                      ? SelectableText(
                          _content!,
                          style: TextStyle(
                            fontFamily: PdflowTypography.mono,
                            fontSize: 12,
                            height: 1.5,
                            color: ink,
                          ),
                        )
                      : MarkdownBody(
                          data: _content!,
                          styleSheet: _mdStyle(context),
                        ),
                ),
        ),
        const SizedBox(height: PdflowSpacing.lg),
        Row(
          children: [
            if (kIsWeb)
              OutlinedButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download, size: 16),
                label: const Text(Strings.download),
              )
            else ...[
              OutlinedButton.icon(
                onPressed: _openFolder,
                icon: const Icon(Icons.folder_open, size: 16),
                label: const Text(Strings.openOutput),
              ),
              const SizedBox(width: PdflowSpacing.sm),
              OutlinedButton.icon(
                onPressed: _copyName,
                icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
                label: Text(_copied ? Strings.copied : Strings.copyPath),
              ),
            ],
            const Spacer(),
            if (widget.onReset != null)
              FilledButton.tonalIcon(
                onPressed: widget.onReset,
                icon: const Icon(Icons.restart_alt, size: 16),
                label: const Text(Strings.convertAnother),
              ),
          ],
        ),
      ],
    );
  }
}

/// Penghitung struktur markdown sederhana (FR-09 preview stats).
class _MdStats {
  int headings = 0;
  int paragraphs = 0;
  int listItems = 0;
  bool _inParagraph = false;

  void countLine(String line) {
    final t = line.trim();
    if (t.startsWith('#')) {
      headings++;
      _inParagraph = false;
    } else if (t.startsWith('- ') || t.startsWith('* ')) {
      listItems++;
      _inParagraph = false;
    } else if (t.isEmpty) {
      _inParagraph = false;
    } else if (!_inParagraph) {
      paragraphs++;
      _inParagraph = true;
    }
  }
}
