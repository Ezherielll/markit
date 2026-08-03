import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/core/converter.dart';
import 'package:pdflow/core/pdf_source.dart';
import 'package:pdflow/core/pdfrx_source.dart';
import 'package:pdflow/models/layout.dart';

import '../helpers/pdf_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdflow_conv_test');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('convert PDF factory → markdown valid (FR-02..07)', () async {
    final src = await PdfrxSource.openData(buildTestPdf());
    final outPath = '${tmp.path}/out.md';
    final progress = <int>[];

    final result = await Converter().convert(
      source: src,
      outputPath: outPath,
      onProgress: (p) => progress.add(p.page),
    );
    await src.dispose();

    expect(result.pageCount, 3);
    expect(result.hasFailures, isFalse);
    expect(progress, [1, 2, 3]);

    final md = File(outPath).readAsStringSync();
    // ignore: avoid_print
    print('--- generated markdown ---\n$md\n---');
    // ignore: avoid_print
    print('--- stats: bodyFontSize=${result.stats.bodyFontSize}, empty=${result.stats.emptyPages} ---');

    expect(md, contains('# The Quick Brown Fox'));
    expect(md, contains('This is the first paragraph of the sample document.'));
    expect(md, contains('- Item one'));
    expect(md, contains('# Chapter Two'));

    // Paragraf terpisah: body dan list tidak menyatu dalam satu paragraf.
    expect(
      md.contains(
        'of the sample document. It spans multiple lines of body text. - Item one',
      ),
      isFalse,
    );

    // .partial tidak tertinggal (D7).
    expect(File('$outPath.partial').existsSync(), isFalse);
  });

  test('cancel: file parsial dihapus, _CancelledException dilempar (FR-11)',
      () async {
    final src = await PdfrxSource.openData(buildTestPdf());
    final outPath = '${tmp.path}/out_cancel.md';

    var cancelled = false;
    await expectLater(
      Converter().convert(
        source: src,
        outputPath: outPath,
        isCancelled: () {
          cancelled = !cancelled;
          return cancelled;
        },
      ),
      throwsA(isA<Exception>()),
    );
    await src.dispose();

    expect(File(outPath).existsSync(), isFalse);
    expect(File('$outPath.partial').existsSync(), isFalse);
  });

  test('page-level failure dicatat, konversi lanjut (FR-10c)', () async {
    final src = await PdfrxSource.openData(buildTestPdf());
    final outPath = '${tmp.path}/out_partial.md';

    // Source wrapper yang sengaja gagal di halaman index 1.
    final failing = _FailingPageSource(src, failAt: 1);
    final result = await Converter().convert(
      source: failing,
      outputPath: outPath,
    );
    await src.dispose();

    expect(result.failedPages, [1]);
    expect(File(outPath).existsSync(), isTrue);
  });
}

class _FailingPageSource implements PdfSource {
  _FailingPageSource(this._inner, {required this.failAt});

  final PdfSource _inner;
  final int failAt;

  @override
  int get pageCount => _inner.pageCount;

  @override
  bool get isEncrypted => _inner.isEncrypted;

  @override
  Future<LightPageData> loadLight(int pageIndex) => _inner.loadLight(pageIndex);

  @override
  Future<List<TextSpan>> loadFull(int pageIndex) async {
    if (pageIndex == failAt) {
      throw StateError('boom');
    }
    return _inner.loadFull(pageIndex);
  }

  @override
  Future<void> dispose() => _inner.dispose();
}
