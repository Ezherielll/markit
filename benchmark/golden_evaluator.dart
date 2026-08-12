/// Evaluator akurasi golden (Task 15).
///
/// Metrik per PRD §4:
/// - Paragraph F1: ordered match unit paragraf antara output vs golden.
/// - Akurasi level heading: % heading golden yang tepat level (hanya # vs ##...).
/// - Recall list: % item list golden yang ada di output.
/// - Noise: baris yang muncul di output tapi tidak di golden (approximate).
///
/// Normalisasi: strip whitespace, lowercase, hapus escaping markdown.
library;

import 'dart:io';

/// Ringkasan hasil evaluasi.
class EvalReport {
  EvalReport({
    required this.paragraphF1,
    required this.headingAccuracy,
    required this.listRecall,
    required this.noiseBlocks,
    required this.headingLevelF1,
    required this.orderedListPrecision,
    required this.wordCompleteness,
    required this.readingOrderScore,
    required this.headerSuppressionRecall,
  });

  final double paragraphF1;
  final double headingAccuracy;
  final double listRecall;
  final List<String> noiseBlocks;

  /// Fase A: F1 (teks, level) heading — hierarki H1/H2/H3 harus tepat.
  final double headingLevelF1;

  /// Fase A: precision item ordered list (teks + index harus cocok).
  final double orderedListPrecision;

  /// Fase A: word recall — teks golden yang muncul di output.
  final double wordCompleteness;

  /// Fase B: Kendall's tau (dinormalisasi ke [0,1]) urutan blok output
  /// vs golden — reading order antar kolom/paragraf.
  final double readingOrderScore;

  /// Fase B: recall konten — memastikan body tidak ikut tersuppress
  /// oleh header/footer filter.
  final double headerSuppressionRecall;

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('paragraph F1: ${(paragraphF1 * 100).toStringAsFixed(1)}%');
    sb.writeln('heading level accuracy: ${(headingAccuracy * 100).toStringAsFixed(1)}%');
    sb.writeln('heading level F1: ${(headingLevelF1 * 100).toStringAsFixed(1)}%');
    sb.writeln('list item recall: ${(listRecall * 100).toStringAsFixed(1)}%');
    sb.writeln('ordered list precision: ${(orderedListPrecision * 100).toStringAsFixed(1)}%');
    sb.writeln('word completeness: ${(wordCompleteness * 100).toStringAsFixed(1)}%');
    sb.writeln('reading order score: ${(readingOrderScore * 100).toStringAsFixed(1)}%');
    sb.writeln('header suppression recall: ${(headerSuppressionRecall * 100).toStringAsFixed(1)}%');
    sb.writeln('noise blocks (extra): ${noiseBlocks.length}');
    for (final n in noiseBlocks.take(5)) {
      sb.writeln('  noise: "$n"');
    }
    return sb.toString();
  }
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('usage: dart run benchmark/golden_evaluator.dart <output.md> <golden.md>');
    exitCode = 1;
    return;
  }
  stdout.write(evaluate(File(args[0]).readAsStringSync(), File(args[1]).readAsStringSync()));
}

/// Evaluasi output vs golden (string). Dipakai langsung oleh run_corpus
/// (tanpa subprocess) dan CLI.
EvalReport evaluate(String output, String golden) {
  final outBlocks = _blocks(_normalize(output));
  final goldenBlocks = _blocks(_normalize(golden));

  return EvalReport(
    paragraphF1: _paragraphF1(outBlocks, goldenBlocks),
    headingAccuracy: _headingAccuracy(outBlocks, goldenBlocks),
    listRecall: _listRecall(outBlocks, goldenBlocks),
    noiseBlocks: _noiseBlocks(outBlocks, goldenBlocks),
    headingLevelF1: _headingLevelF1(outBlocks, goldenBlocks),
    orderedListPrecision: _orderedListPrecision(outBlocks, goldenBlocks),
    wordCompleteness: _wordCompleteness(output, golden),
    readingOrderScore: _readingOrderScore(outBlocks, goldenBlocks),
    headerSuppressionRecall: _headerSuppressionRecall(outBlocks, goldenBlocks),
  );
}

typedef _Block = ({String type, String text, int level, int? listIndex});

List<_Block> _blocks(String normalized) {
  final blocks = <_Block>[];
  String? pending;
  for (final rawLine in normalized.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) {
      pending = null;
      continue;
    }
    String? type;
    String text = line;
    var level = 0;
    int? listIndex;
    if (line.startsWith('#')) {
      type = 'heading';
      level = line.length - line.replaceFirst(RegExp(r'^#+'), '').length;
      text = line.replaceFirst(RegExp(r'^#+\s*'), '');
    } else if (line.startsWith('- ')) {
      type = 'list';
      text = line.substring(2);
    } else if (RegExp(r'^\d+[.)]\s').hasMatch(line)) {
      type = 'list';
      listIndex = int.tryParse(RegExp(r'^\d+').firstMatch(line)?.group(0) ?? '');
      text = line.replaceFirst(RegExp(r'^\d+[.)]\s*'), '');
    } else {
      type = 'paragraph';
    }
    if (pending != null) {
      blocks[blocks.length - 1] = (
        type: blocks.last.type,
        text: '${blocks.last.text} $line',
        level: blocks.last.level,
        listIndex: blocks.last.listIndex,
      );
      pending = null;
      continue;
    }
    blocks.add((type: type, text: text, level: level, listIndex: listIndex));
  }
  return blocks;
}

double _paragraphF1(List<_Block> out, List<_Block> golden) {
  final outPara = out.where((b) => b.type != 'heading' && b.type != 'list').toList();
  final goldPara = golden.where((b) => b.type != 'heading' && b.type != 'list').toList();
  final outSet = outPara.map((b) => b.text).toSet();
  final goldSet = goldPara.map((b) => b.text).toSet();
  final tp = outSet.intersection(goldSet).length;
  if (tp == 0) return 0;
  final precision = tp / outSet.length;
  final recall = tp / goldSet.length;
  return 2 * precision * recall / (precision + recall);
}

double _headingAccuracy(List<_Block> out, List<_Block> golden) {
  final goldHead = golden.where((b) => b.type == 'heading').map((b) => b.text);
  final outHead = out.where((b) => b.type == 'heading').map((b) => b.text).toSet();
  if (goldHead.isEmpty) return 1.0;
  var hit = 0;
  for (final h in goldHead) {
    if (outHead.contains(h)) hit++;
  }
  return hit / goldHead.length;
}

double _listRecall(List<_Block> out, List<_Block> golden) {
  final goldList = golden.where((b) => b.type == 'list').map((b) => b.text);
  final outList = out.where((b) => b.type == 'list').map((b) => b.text).toSet();
  if (goldList.isEmpty) return 1.0;
  var hit = 0;
  for (final l in goldList) {
    if (outList.contains(l)) hit++;
  }
  return hit / goldList.length;
}

List<String> _noiseBlocks(List<_Block> out, List<_Block> golden) {
  final goldSet = golden.map((b) => b.text).toSet();
  return out.map((b) => b.text).where((t) => !goldSet.contains(t)).toList();
}

/// Fase A: F1 pasangan (teks, level) heading — level salah dihitung salah.
double _headingLevelF1(List<_Block> out, List<_Block> golden) {
  final goldHead =
      golden.where((b) => b.type == 'heading').map((b) => (b.text, b.level)).toSet();
  final outHead =
      out.where((b) => b.type == 'heading').map((b) => (b.text, b.level)).toList();
  if (goldHead.isEmpty) return outHead.isEmpty ? 1.0 : 0.0;
  if (outHead.isEmpty) return 0.0;
  var tp = 0;
  for (final h in outHead) {
    if (goldHead.contains(h)) tp++;
  }
  if (tp == 0) return 0.0;
  final precision = tp / outHead.length;
  final recall = tp / goldHead.length;
  return 2 * precision * recall / (precision + recall);
}

/// Fase A: precision item ordered list — (teks, index) harus cocok.
double _orderedListPrecision(List<_Block> out, List<_Block> golden) {
  final goldOrdered = golden
      .where((b) => b.type == 'list' && b.listIndex != null)
      .map((b) => (b.text, b.listIndex))
      .toSet();
  final outOrdered = out
      .where((b) => b.type == 'list' && b.listIndex != null)
      .map((b) => (b.text, b.listIndex))
      .toList();
  if (outOrdered.isEmpty) return goldOrdered.isEmpty ? 1.0 : 0.0;
  if (goldOrdered.isEmpty) return 0.0;
  var tp = 0;
  for (final item in outOrdered) {
    if (goldOrdered.contains(item)) tp++;
  }
  return tp / outOrdered.length;
}

/// Fase A: word recall — fraksi kata golden yang muncul di output.
double _wordCompleteness(String output, String golden) {
  final goldWords = _words(golden);
  if (goldWords.isEmpty) return 1.0;
  final outWords = _words(output).toSet();
  var hit = 0;
  for (final w in goldWords) {
    if (outWords.contains(w)) hit++;
  }
  return hit / goldWords.length;
}

List<String> _words(String s) => s
    .replaceAll('\\', '')
    .toLowerCase()
    .split(RegExp(r'[^a-z0-9]+'))
    .where((w) => w.isNotEmpty)
    .toList();

/// Fase B: Kendall's tau antara urutan block output dan golden,
/// dinormalisasi ke [0,1] (tau=-1 → 0, tau=0 → 0.5, tau=1 → 1).
/// Hanya block yang ada di golden yang dihitung (noise diabaikan).
double _readingOrderScore(List<_Block> out, List<_Block> golden) {
  final goldenRank = <String, int>{};
  for (var i = 0; i < golden.length; i++) {
    goldenRank[golden[i].text] = i;
  }

  final filtered = out.where((b) => goldenRank.containsKey(b.text)).toList();
  if (filtered.length < 2) return 1.0; // tidak cukup data

  var concordant = 0;
  var discordant = 0;
  for (var i = 0; i < filtered.length; i++) {
    for (var j = i + 1; j < filtered.length; j++) {
      final ri = goldenRank[filtered[i].text]!;
      final rj = goldenRank[filtered[j].text]!;
      if (ri < rj) {
        concordant++;
      } else if (ri > rj) {
        discordant++;
      }
      // ties diabaikan
    }
  }

  final total = concordant + discordant;
  if (total == 0) return 1.0;

  final tau = (concordant - discordant) / total;
  return (tau + 1) / 2;
}

/// Fase B: recall konten golden yang ada di output — memastikan
/// header/footer suppression tidak menghilangkan body text.
double _headerSuppressionRecall(List<_Block> out, List<_Block> golden) {
  if (golden.isEmpty) return 1.0;
  final outTexts = out.map((b) => b.text).toSet();
  var hit = 0;
  for (final g in golden) {
    if (outTexts.contains(g.text)) hit++;
  }
  return hit / golden.length;
}

String _normalize(String s) {
  return s.replaceAll('\\', '').trim();
}
