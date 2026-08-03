import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/core/errors.dart';
import 'package:pdflow/core/pdf_source.dart';
import 'package:pdflow/core/pdfrx_source.dart';
import 'package:pdflow/models/layout.dart';
import 'package:pdfrx/pdfrx.dart';

import '../helpers/pdf_factory.dart';

void main() {
  group('TextSpan/Line geometry', () {
    test('yCenter, height, fontSize proxy', () {
      final span = TextSpan(
        text: 'hello',
        xLeft: 10,
        xRight: 60,
        yBottom: 100,
        yTop: 112,
        fontSize: 12,
      );
      expect(span.xCenter, 35);
      expect(span.yCenter, 106);
      expect(span.height, 12);
      expect(span.width, 50);
    });

    test('Line aggregates spans', () {
      final line = Line(spans: [
        TextSpan(text: 'The ', xLeft: 0, xRight: 25, yBottom: 0, yTop: 12, fontSize: 12),
        TextSpan(text: 'Fox', xLeft: 25, xRight: 50, yBottom: 0, yTop: 14, fontSize: 14),
      ]);
      expect(line.text, 'The Fox');
      expect(line.height, 14);
      expect(line.fontSize, 14);
      expect(line.yCenter, 7);
    });
  });

  group('mapOpenError (FR-10a/b)', () {
    test('password exception -> encrypted', () {
      final e = mapOpenError(PdfPasswordException('No password supplied by PasswordProvider.'));
      expect(e.type, ConvertError.encrypted);
    });

    test('other exception -> corrupt', () {
      final e = mapOpenError(StateError('boom'));
      expect(e.type, ConvertError.corrupt);
    });
  });

  group('PdfrxSource smoke (file factory)', () {
    test('open + loadLight + loadFull + dispose', () async {
      final src = await PdfrxSource.openData(buildTestPdf());
      expect(src.pageCount, 3);
      expect(src.isEncrypted, isFalse);

      final light = await src.loadLight(0);
      expect(light.hasText, isTrue);
      expect(light.charCount, greaterThan(0));
      expect(light.lineHeights, isNotEmpty);

      final spans = await src.loadFull(0);
      expect(spans, isNotEmpty);
      final joined = spans.map((s) => s.text).join();
      expect(joined, contains('The Quick Brown Fox'));

      // Heading (24pt) harus lebih "besar" daripada body (12pt).
      final headingFont = spans.firstWhere((s) => s.text.contains('Quick')).fontSize;
      final bodyFont = spans.firstWhere((s) => s.text.contains('paragraph')).fontSize;
      expect(headingFont, greaterThan(bodyFont * 1.5));

      await src.dispose();
    });
  });
}
