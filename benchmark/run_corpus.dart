import 'dart:io';

import 'package:markit/core/converter.dart';
import 'package:markit/core/output.dart';

import 'engine_source.dart';
import 'golden_evaluator.dart';

/// Ambang akurasi per jenis dokumen (PRD §4).
/// - single-column book: F1 paragraf ≥ 0.90 (exit criteria M0)
/// - tabel sederhana: baseline v2 (FR-23), di sini hanya dicatat.
double _thresholdFor(String name) {
  if (name.startsWith('with_tables')) return 0.60;
  return 0.90;
}

/// Runner korpus: convert semua `corpus/pdfs/*.pdf` → markdown via pipeline
/// penuh (Converter), lalu evaluasi terhadap `corpus/golden/{name}.md`.
///
/// Usage: `dart run benchmark/run_corpus.dart [name.pdf]`
///
/// Menulis ringkasan ke docs/benchmark.md. Exit 1 bila ada file di bawah
/// ambang PRD §4.
void main(List<String> args) async {
  final pdfDir = Directory('corpus/pdfs');
  if (!pdfDir.existsSync()) {
    stderr.writeln('corpus/pdfs tidak ada. Jalankan dulu: dart run benchmark/make_corpus.dart');
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
      stdout.writeln('  SKIP evaluasi (belum ada golden)');
      report.writeln('- $name: (no golden)');
      continue;
    }

    final reportEval = evaluate(
      File(outMd).readAsStringSync(),
      File(golden).readAsStringSync(),
    );
    stdout.writeln(reportEval.toString());

    final f1 = reportEval.paragraphF1;
    final threshold = _thresholdFor(name);
    final pass = f1 >= threshold;
    allPass = allPass && pass;
    report.writeln(
        '- $name: F1 ${(f1 * 100).toStringAsFixed(1)}% (threshold ${(threshold * 100).toStringAsFixed(0)}%) '
        '${pass ? 'PASS' : 'FAIL'} · ${sw.elapsedMilliseconds} ms');
  }

  File('docs/benchmark.md').writeAsStringSync(
    '${File('docs/benchmark.md').existsSync() ? File('docs/benchmark.md').readAsStringSync() : ''}\n$report',
  );
  stdout.writeln(allPass ? 'CORPUS: all pass' : 'CORPUS: some failed');
  if (!allPass) exitCode = 1;
}
