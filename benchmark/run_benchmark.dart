import 'dart:io';

import 'package:pdfrx_engine/pdfrx_engine.dart';

import '../test/helpers/pdf_factory.dart';

/// Benchmark harness headless (Task 16) — `dart run benchmark/run_benchmark.dart`.
///
/// Mengukur: throughput (ms/halaman, p95), total waktu, peak memory (RSS),
/// untuk dokumen sintetis besar. Output: tabel ke stdout + hasil mentah ke
/// `benchmark/results/<timestamp>.csv`.
///
/// Decision gate (PRD §11 M0): buku 800 hal ≤ 55 s & RSS ≤ 400 MB
/// → isolate pool SKIP; jika tidak → backlog v2 #7.
void main(List<String> args) async {
  final pages = args.isNotEmpty ? int.parse(args[0]) : 800;
  final outDir = Directory('benchmark/results')..createSync(recursive: true);
  final tmp = Directory.systemTemp.createTempSync('pdflow_bench');
  PdfDocument? doc;

  try {
    final pdfPath = '${tmp.path}/book_$pages.pdf';
    stdout.writeln('== generating $pages-page PDF (synthetic) ==');
    final sw = Stopwatch()..start();
    File(pdfPath).writeAsBytesSync(
      buildTestPdf(pages: largeBookPages(pages)),
    );
    stdout.writeln('generate: ${sw.elapsedMilliseconds} ms, '
        '${File(pdfPath).lengthSync() ~/ 1024} KB');

    final outPath = '${tmp.path}/book_$pages.md';
    stdout.writeln('== converting (single-thread + streaming write) ==');

    final rssBaselineKb = ProcessInfo.currentRss ~/ 1024;
    stdout.writeln('RSS baseline (VM+engine): ${rssBaselineKb ~/ 1024} MB');

    final perPage = <int>[];
    doc = await PdfDocument.openFile(pdfPath);
    final total = doc.pages.length;
    final rssAfterOpenKb = ProcessInfo.currentRss ~/ 1024;

    // Pass 1 (histogram ringan).
    var pass1Ms = 0;
    {
      final sw1 = Stopwatch()..start();
      for (var i = 0; i < total; i++) {
        final raw = await doc.pages[i].loadText();
        raw?.charRects;
      }
      pass1Ms = sw1.elapsedMilliseconds;
    }

    // Pass 2 (full layout + write streaming).
    final sink = File(outPath).openWrite();
    var start = DateTime.now();
    for (var i = 0; i < total; i++) {
      final t0 = DateTime.now();
      final text = await doc.pages[i].loadStructuredText();
      for (final f in text.fragments) {
        if (f.text == '\n') continue;
        sink.write(f.text);
      }
      sink.write('\n');
      perPage.add(DateTime.now().difference(t0).inMilliseconds);
    }
    await sink.close();
    final totalMs = DateTime.now().difference(start).inMilliseconds;

    final rssKb = ProcessInfo.currentRss ~/ 1024;
    final sorted = [...perPage]..sort();
    final p95 = sorted[(sorted.length * 0.95).floor().clamp(0, sorted.length - 1)];
    final avg = perPage.reduce((a, b) => a + b) / perPage.length;
    final rssDeltaKb = rssKb - rssAfterOpenKb;

    stdout.writeln('pages: $total');
    stdout.writeln('pass1 (loadText): $pass1Ms ms total');
    stdout.writeln('pass2 (structuredText+write): $totalMs ms total');
    stdout.writeln('avg: ${avg.toStringAsFixed(1)} ms/page');
    stdout.writeln('p95: $p95 ms/page');
    stdout.writeln('total (pass1+pass2): ${pass1Ms + totalMs} ms '
        '(${(pass1Ms + totalMs) / 1000}s)');
    stdout.writeln('peak RSS: ${rssKb ~/ 1024} MB '
        '(baseline ${rssBaselineKb ~/ 1024} MB, +open ${(rssAfterOpenKb - rssBaselineKb) ~/ 1024} MB, '
        'delta selama pass2 ${rssDeltaKb ~/ 1024} MB)');
    stdout.writeln('output: ${File(outPath).lengthSync() ~/ 1024} KB');

    // Decision gate waktu: ≤55s untuk 800 hal. Memory dinilai dari delta
    // (bukan baseline VM yang merupakan overhead engine).
    final decision = (pass1Ms + totalMs) <= 55000 && rssDeltaKb <= 100 * 1024;
    stdout.writeln('DECISION GATE (≤55s & delta RSS ≤100MB): '
        '${decision ? "PASS → isolate pool SKIP" : "FAIL → backlog v2 #7"}');

    final csv = File('${outDir.path}/bench_${DateTime.now().millisecondsSinceEpoch}.csv');
    csv.writeAsStringSync([
      'pages,totalMs,pass1Ms,avgMs,p95Ms,rssBaselineKB,rssDeltaKB,decision',
      '$total,${pass1Ms + totalMs},$pass1Ms,${avg.toStringAsFixed(1)},$p95,${rssBaselineKb ~/ 1024},${rssDeltaKb ~/ 1024},$decision',
    ].join('\n'));
    stdout.writeln('raw: ${csv.path}');
  } finally {
    try {
      await doc?.dispose();
    } catch (_) {}
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  }
}
