import 'dart:io';

import 'package:markit/core/converter.dart';
import 'package:markit/core/output.dart';

import 'engine_source.dart';
import 'golden_evaluator.dart';

/// Accuracy threshold per document type (PRD §4 + Phase A/B/C).
/// - single-column book: paragraph F1 >= 0.90 (M0 exit criteria)
/// - simple table: tableCellF1
/// - multi-page table: tableCellF1 (Phase D)
/// - nested list: nestedListRecall
/// - Phase A fixtures: headingLevelF1 / orderedListPrecision.
/// - Phase B fixtures: readingOrderScore / headerSuppressionRecall.
double _thresholdFor(String name) {
  if (name.startsWith('simple_table')) return 0.70; // tableCellF1
  if (name.startsWith('multi_page_table')) return 0.70; // tableCellF1
  if (name.startsWith('mixed_table')) return 0.70; // tableCellF1
  if (name.startsWith('nested_list')) return 0.80; // nestedListRecall
  if (name.startsWith('nested_headings')) return 0.85;
  if (name.startsWith('numbered_sections')) return 0.80;
  if (name.startsWith('ordered_list')) return 0.80;
  if (name.startsWith('multi_column_paper')) return 0.80; // readingOrderScore
  if (name.startsWith('header_footer')) return 0.90; // headerSuppressionRecall
  return 0.90;
}

/// Primary metric per fixture + its value. Fallback: paragraphF1.
(double, String) _primaryMetric(String name, EvalReport r) {
  if (name.startsWith('simple_table')) {
    return (r.tableCellF1, 'tableCellF1');
  }
  if (name.startsWith('multi_page_table')) {
    return (r.tableCellF1, 'tableCellF1');
  }
  if (name.startsWith('mixed_table')) {
    return (r.tableCellF1, 'tableCellF1');
  }
  if (name.startsWith('nested_list')) {
    return (r.nestedListRecall, 'nestedListRecall');
  }
  if (name.startsWith('nested_headings') || name.startsWith('numbered_sections')) {
    return (r.headingLevelF1, 'headingLevelF1');
  }
  if (name.startsWith('ordered_list')) {
    return (r.orderedListPrecision, 'orderedListPrecision');
  }
  if (name.startsWith('multi_column_paper')) {
    return (r.readingOrderScore, 'readingOrderScore');
  }
  if (name.startsWith('header_footer')) {
    return (r.headerSuppressionRecall, 'headerSuppressionRecall');
  }
  return (r.paragraphF1, 'paragraphF1');
}

/// Corpus runner: converts all `corpus/pdfs/*.pdf` -> markdown via full
/// pipeline (Converter), then evaluates against `corpus/golden/{name}.md`.
///
/// Usage: `dart run benchmark/run_corpus.dart [name.pdf]`
///
/// Writes summary to docs/benchmark.md. Exits 1 if any file falls below PRD §4 threshold.
void main(List<String> args) async {
  final pdfDir = Directory('corpus/pdfs');
  if (!pdfDir.existsSync()) {
    stderr.writeln('corpus/pdfs does not exist. Run first: dart run benchmark/make_corpus.dart');
    exitCode = 1;
    return;
  }

  final files = args.isEmpty
      ? pdfDir.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')).toList()
      : [File('corpus/pdfs/${args[0]}')];

  final report = StringBuffer()..writeln('## Corpus run ${DateTime.now().toIso8601String()}');
  var allPass = true;

  for (final pdf in files) {
    final name = pdf.uri.pathSegments.last.replaceAll('.pdf', '');
    final outMd = 'corpus/out/$name.md';
    final golden = 'corpus/golden/$name.md';
    Directory('corpus/out').createSync(recursive: true);

    stdout.writeln('== $name ==');
    final sw = Stopwatch()..start();
    final source = await EnginePdfSource.open(pdf.path);
    try {
      await Converter().convert(source: source, output: FileOutput(outMd));
    } finally {
      await source.dispose();
    }
    sw.stop();
    stdout.writeln('  convert: ${sw.elapsedMilliseconds} ms');

    if (!File(golden).existsSync()) {
      stdout.writeln('  SKIP evaluation (golden reference missing)');
      report.writeln('- $name: (no golden)');
      continue;
    }

    final reportEval = evaluate(
      File(outMd).readAsStringSync(),
      File(golden).readAsStringSync(),
    );
    stdout.writeln(reportEval.toString());

    final (value, metric) = _primaryMetric(name, reportEval);
    final threshold = _thresholdFor(name);
    final pass = value >= threshold;
    allPass = allPass && pass;
    report.writeln(
        '- $name: $metric ${(value * 100).toStringAsFixed(1)}% (threshold ${(threshold * 100).toStringAsFixed(0)}%) '
        '${pass ? 'PASS' : 'FAIL'} · ${sw.elapsedMilliseconds} ms');
  }

  File('docs/benchmark.md').writeAsStringSync(
    '${File('docs/benchmark.md').existsSync() ? File('docs/benchmark.md').readAsStringSync() : ''}\n$report',
  );
  stdout.writeln(allPass ? 'CORPUS: all pass' : 'CORPUS: some failed');
  if (!allPass) exitCode = 1;
}
