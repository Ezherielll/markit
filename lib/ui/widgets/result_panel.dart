import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';
import 'package:pdflow/ui/widgets/stat_chip.dart';
import 'package:url_launcher/url_launcher.dart';

/// Panel hasil (FR-09): preview markdown di-render seperti halaman kertas
/// (toggle Rendered/Raw), stat chips, aksi open folder / copy path / ulang.
class ResultPanel extends StatefulWidget {
  const ResultPanel({
    super.key,
    required this.outputPath,
    required this.onReset,
    this.failedPages = const [],
  });

  final String outputPath;
  final VoidCallback onReset;

  /// Halaman gagal (1-based) — ditampilkan sebagai warning (FR-10c).
  final List<int> failedPages;

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
    final file = File(widget.outputPath);
    if (!await file.exists()) return;

    // Preview: baca sebagian kecil saja (file bisa ratusan KB/ribuan halaman).
    final raf = await file.open();
    String preview;
    try {
      final chunk = await raf.read(128 * 1024);
      preview = utf8.decode(chunk, allowMalformed: true);
    } finally {
      await raf.close();
    }

    // Stats struktur: scan streaming seluruh file, hitung per baris.
    final stats = _MdStats();
    await for (final line in file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter())) {
      stats.countLine(line);
    }
    if (!mounted) return;
    setState(() {
      _content = preview;
      _stats = stats;
    });
  }

  Future<void> _openFolder() async {
    final dir = File(widget.outputPath).parent.path;
    final ok = await launchUrl(Uri.file(dir));
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open folder.')),
      );
    }
  }

  Future<void> _copyPath() async {
    await Clipboard.setData(ClipboardData(text: widget.outputPath));
    if (!mounted) return;
    setState(() => _copied = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(Strings.copied)),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    if (mounted) setState(() => _copied = false);
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
    final name = widget.outputPath.split(Platform.pathSeparator).last;

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
        if (widget.failedPages.isNotEmpty) ...[
          const SizedBox(height: PdflowSpacing.sm),
          Text(
            Strings.warningFailedPages.replaceFirst('%d', '${widget.failedPages.length}'),
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
            OutlinedButton.icon(
              onPressed: _openFolder,
              icon: const Icon(Icons.folder_open, size: 16),
              label: const Text(Strings.openOutput),
            ),
            const SizedBox(width: PdflowSpacing.sm),
            OutlinedButton.icon(
              onPressed: _copyPath,
              icon: Icon(_copied ? Icons.check : Icons.copy, size: 16),
              label: Text(_copied ? Strings.copied : Strings.copyPath),
            ),
            const Spacer(),
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
