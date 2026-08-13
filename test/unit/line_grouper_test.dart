import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/doc_stats.dart';
import 'package:markit/core/line_grouper.dart';
import 'package:markit/models/layout.dart';

TextSpan _span(String text, {double x = 0, double y = 100, double h = 12}) =>
    TextSpan(
      text: text,
      xLeft: x,
      xRight: x + text.length * 6,
      yBottom: y - h,
      yTop: y,
      fontSize: h,
    );

void main() {
  final grouper = LineGrouper();

  group('LineGrouper (FR-03)', () {
    test('span sebaris → satu baris, urut left-to-right', () {
      final lines = grouper.group([
        _span('fox', x: 40),
        _span('The ', x: 0),
        _span('brown ', x: 20),
      ]);
      expect(lines, hasLength(1));
      expect(lines.first.text, 'The brown fox');
    });

    test('dua baris terpisah vertikal → dua baris, top-to-bottom', () {
      final lines = grouper.group([
        _span('line A', y: 120),
        _span('line B', y: 100),
      ]);
      expect(lines, hasLength(2));
      expect(lines[0].text, 'line A');
      expect(lines[1].text, 'line B');
    });

    test('span dengan y sedikit bergeser tetap sebaris', () {
      final lines = grouper.group([
        _span('abc', y: 120),
        _span('def', y: 119.5),
        _span('ghi', y: 119),
      ]);
      expect(lines, hasLength(1));
      expect(lines.first.text, 'abcdefghi');
    });

    test('gabungan: 2 baris dengan multi-span tiap baris', () {
      final lines = grouper.group([
        _span('a', x: 0, y: 140, h: 18), // heading-ish
        _span('b', x: 10, y: 140, h: 18),
        _span('c', x: 0, y: 100), // body line 1
        _span('d', x: 6, y: 100), // bersambung tanpa gap
        _span('e', x: 0, y: 80), // body line 2
      ]);
      expect(lines, hasLength(3));
      expect(lines[0].text, 'ab');
      expect(lines[1].text, 'cd');
      expect(lines[2].text, 'e');
    });
  });

  group('Word spacing normalization (Fase B)', () {
    test('gap besar antar fragment dalam satu baris → tambah spasi', () {
      // Dua span pada y yang sama tapi ada gap besar (> 0.3 * fontSize = 3.6pt)
      // Span A: x=72..150, span B: x=160..220 → gap = 10pt > 3.6pt → tambah spasi
      final g = LineGrouper();
      final spans = [
        TextSpan(text: 'Hello', xLeft: 72, xRight: 150, yBottom: 688, yTop: 700, fontSize: 12),
        TextSpan(text: 'World', xLeft: 160, xRight: 220, yBottom: 688, yTop: 700, fontSize: 12),
      ];
      final lines = g.group(spans);
      expect(lines, hasLength(1));
      // Teks harus mengandung spasi di antara Hello dan World
      expect(lines.first.text, 'Hello World');
    });

    test('gap kecil antar fragment → tidak tambah spasi ekstra', () {
      // Gap 2pt < 0.3 * 12 = 3.6pt → tidak tambah spasi
      final g = LineGrouper();
      final spans = [
        TextSpan(text: 'Hello', xLeft: 72, xRight: 102, yBottom: 688, yTop: 700, fontSize: 12),
        TextSpan(text: 'World', xLeft: 104, xRight: 164, yBottom: 688, yTop: 700, fontSize: 12),
      ];
      final lines = g.group(spans);
      expect(lines, hasLength(1));
      expect(lines.first.text, 'HelloWorld'); // tidak ada spasi karena gap kecil
    });

    test('teks yang sudah mengandung trailing space tidak dapat spasi ganda', () {
      final g = LineGrouper();
      final spans = [
        TextSpan(text: 'Hello ', xLeft: 72, xRight: 102, yBottom: 688, yTop: 700, fontSize: 12),
        TextSpan(text: 'World', xLeft: 110, xRight: 170, yBottom: 688, yTop: 700, fontSize: 12),
      ];
      final lines = g.group(spans);
      expect(lines.first.text, isNot(contains('  '))); // tidak ada double space
    });

    test('LineGrouper menerima DocProfile opsional (backward compat)', () {
      final withProfile = LineGrouper(config: const PipelineConfig(), profile: _profile612());
      final without = LineGrouper();
      expect(withProfile.config, isNotNull);
      expect(without.profile, isNull);
    });
  });
}

DocProfile _profile612() => DocProfile(
      bodyFontSize: 12,
      headingBands: const [],
      totalPages: 1,
      emptyPages: 0,
      pageWidth: 612,
      pageHeight: 792,
      bodyLeftMargin: 72,
      bodyRightMargin: 540,
    );
