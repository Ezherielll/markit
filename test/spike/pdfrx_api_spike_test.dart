import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/pdf_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_spike');
  });
  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('spike: open, structured text, font-size proxy, timing', () async {
    final file = File('${tmp.path}/sample.pdf')
      ..writeAsBytesSync(buildTestPdf());

    final sw = Stopwatch()..start();
    final doc = await PdfDocument.openFile(file.path);
    sw.stop();
    // ignore: avoid_print
    print(
      '[spike] open: ${sw.elapsedMilliseconds} ms, pages=${doc.pages.length}, '
      'encrypted=${doc.isEncrypted}',
    );

    final page = doc.pages[0];
    final text = await page.loadStructuredText();
    // ignore: avoid_print
    print('[spike] fullText page 1: "${text.fullText}"');
    // ignore: avoid_print
    print('[spike] fragments page 1: ${text.fragments.length}');
    for (final f in text.fragments) {
      final h = f.charRects.isEmpty
          ? 0.0
          : f.charRects.map((r) => r.height).reduce((a, b) => a > b ? a : b);
      // ignore: avoid_print
      print(
        '[spike]   frag: "${f.text}" bounds=${f.bounds} dir=${f.direction.name} '
        'maxCharH=${h.toStringAsFixed(2)}',
      );
    }

    final raw = await page.loadText();
    // ignore: avoid_print
    print(
      '[spike] loadText: chars=${raw?.fullText.length} charRects=${raw?.charRects.length}',
    );

    final sw2 = Stopwatch()..start();
    for (var i = 0; i < doc.pages.length; i++) {
      await doc.pages[i].loadStructuredText();
    }
    sw2.stop();
    // ignore: avoid_print
    print(
      '[spike] structuredText ${doc.pages.length} pages: ${sw2.elapsedMilliseconds} ms '
      '(${sw2.elapsedMilliseconds / doc.pages.length} ms/page)',
    );

    // Page order sanity check (pageNumber is 1-based).
    expect(doc.pages.length, 3);
    expect(text.fullText, contains('The Quick Brown Fox'));

    await doc.dispose();
  });

  test('spike: corrupt pdf raises error, not hang', () async {
    final file = File('${tmp.path}/corrupt.pdf')
      ..writeAsBytesSync(List.filled(2048, 0x42));

    Object? err;
    try {
      await PdfDocument.openFile(file.path);
    } catch (e) {
      err = e;
    }
    // ignore: avoid_print
    print('[spike] corrupt error: ${err.runtimeType}: $err');
    expect(err, isNotNull);
  });
}
