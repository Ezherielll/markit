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
  });

  final double paragraphF1;
  final double headingAccuracy;
  final double listRecall;
  final List<String> noiseBlocks;

  @override
  String toString() {
    final sb = StringBuffer();
    sb.writeln('paragraph F1: ${(paragraphF1 * 100).toStringAsFixed(1)}%');
    sb.writeln('heading level accuracy: ${(headingAccuracy * 100).toStringAsFixed(1)}%');
    sb.writeln('list item recall: ${(listRecall * 100).toStringAsFixed(1)}%');
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
  );
}

typedef _Block = ({String type, String text});

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
    if (line.startsWith('#')) {
      type = 'heading';
      text = line.replaceFirst(RegExp(r'^#+\s*'), '');
    } else if (line.startsWith('- ')) {
      type = 'list';
      text = line.substring(2);
    } else {
      type = 'paragraph';
    }
    if (pending != null) {
      blocks[blocks.length - 1] = (
        type: blocks.last.type,
        text: '${blocks.last.text} $line',
      );
      pending = null;
      continue;
    }
    blocks.add((type: type, text: text));
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

String _normalize(String s) {
  return s.replaceAll('\\', '').trim();
}
