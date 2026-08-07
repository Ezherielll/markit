import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/typography.dart';

/// Potong konten untuk preview — memotong di batas baris agar markdown tetap
/// valid. Return (preview, apakah terpotong).
({String preview, bool truncated}) truncateMarkdownPreview(
  String content, {
  required int maxChars,
}) {
  if (content.length <= maxChars) {
    return (preview: content, truncated: false);
  }
  var cut = content.lastIndexOf('\n', maxChars);
  if (cut <= 0) cut = maxChars;
  // Potong di akhir baris (termasuk newline) agar baris terakhir utuh.
  if (cut < content.length && content[cut] == '\n') cut++;
  return (
    preview: content.substring(0, cut),
    truncated: true,
  );
}

/// Penghitung struktur markdown sederhana (heading/paragraf/list/tabel).
/// Baris di dalam fenced code block (` ``` `) TIDAK dihitung — itu konten
/// data (JSON/XML), bukan paragraf dokumen.
class MdStats {
  int headings = 0;
  int paragraphs = 0;
  int listItems = 0;

  /// Baris tabel markdown (`| … |`) — ditampilkan sebagai "rows".
  int tableRows = 0;
  bool _inParagraph = false;
  bool _inCodeBlock = false;

  void countLine(String line) {
    final t = line.trim();
    if (t.startsWith('```')) {
      _inCodeBlock = !_inCodeBlock;
      _inParagraph = false;
      return;
    }
    if (_inCodeBlock) return;
    if (t.startsWith('#')) {
      headings++;
      _inParagraph = false;
    } else if (t.startsWith('- ') || t.startsWith('* ')) {
      listItems++;
      _inParagraph = false;
    } else if (t.startsWith('|') && t.endsWith('|')) {
      tableRows++;
      _inParagraph = false;
    } else if (t.isEmpty) {
      _inParagraph = false;
    } else if (!_inParagraph) {
      paragraphs++;
      _inParagraph = true;
    }
  }
}

MdStats computeMdStats(String content) {
  final stats = MdStats();
  for (final line in const LineSplitter().convert(content)) {
    stats.countLine(line);
  }
  return stats;
}

/// Style sheet markdown "document reader" — tipografi editorial yang nyaman
/// dibaca (Notion/Obsidian-like): serif display untuk heading, body legible.
MarkdownStyleSheet documentMarkdownStyle(BuildContext context) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
  final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
  final primary = Theme.of(context).colorScheme.primary;
  final base = MarkdownStyleSheet.fromTheme(Theme.of(context));

  return base.copyWith(
    h1: TextStyle(
      fontFamily: PdflowTypography.display,
      fontSize: 26,
      height: 1.2,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      color: ink,
    ),
    h2: TextStyle(
      fontFamily: PdflowTypography.display,
      fontSize: 21,
      height: 1.25,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      color: ink,
    ),
    h3: TextStyle(
      fontFamily: PdflowTypography.display,
      fontSize: 17,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    h4: TextStyle(
      fontFamily: PdflowTypography.ui,
      fontSize: 15,
      height: 1.35,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    p: const TextStyle(
      fontFamily: PdflowTypography.ui,
      fontSize: 14.5,
      height: 1.7,
      letterSpacing: 0.1,
    ),
    listBullet: TextStyle(fontSize: 14.5, height: 1.7, color: inkMuted),
    blockquote: TextStyle(
      fontFamily: PdflowTypography.ui,
      fontSize: 14.5,
      height: 1.7,
      fontStyle: FontStyle.italic,
      color: inkMuted,
    ),
    blockquoteDecoration: BoxDecoration(
      border: Border(left: BorderSide(color: primary, width: 3)),
      color: primary.withValues(alpha: 0.05),
    ),
    code: TextStyle(
      fontFamily: PdflowTypography.mono,
      fontSize: 12.5,
      height: 1.5,
      color: primary,
      backgroundColor: primary.withValues(alpha: 0.08),
    ),
    codeblockDecoration: BoxDecoration(
      color: primary.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(8),
    ),
    tableHead: TextStyle(
      fontFamily: PdflowTypography.ui,
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: ink,
    ),
    tableHeadAlign: TextAlign.left,
    // Max(Intrinsic, Flex): tabel sempit tetap mengisi lebar (flex), tabel
    // lebar (CSV banyak kolom) → Intrinsic → horizontal scroll muncul,
    // bukan cell dipaksa rapat/terpotong (plan M1).
    tableColumnWidth: MaxColumnWidth(
      IntrinsicColumnWidth(),
      FlexColumnWidth(),
    ),
    tableBody: TextStyle(
      fontFamily: PdflowTypography.ui,
      fontSize: 13,
      height: 1.5,
      color: ink,
    ),
    tablePadding: const EdgeInsets.only(bottom: 8),
    tableScrollbarThumbVisibility: true,
    horizontalRuleDecoration: BoxDecoration(
      border: Border(
        top: BorderSide(
          color: isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight,
        ),
      ),
    ),
  );
}
