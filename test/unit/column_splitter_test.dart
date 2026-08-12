import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/column_splitter.dart';
import 'package:markit/core/doc_stats.dart';
import 'package:markit/models/layout.dart';

// Helper: buat span di posisi tertentu
TextSpan _span(String text, double x, double y, {double h = 12}) => TextSpan(
      text: text,
      xLeft: x,
      xRight: x + text.length * 6.0,
      yBottom: y - h,
      yTop: y,
      fontSize: h,
    );

// Profile untuk halaman 612x792
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

void main() {
  group('ColumnSplitter', () {
    final splitter = ColumnSplitter();

    test('single-column: semua spans di area kiri → 1 kolom', () {
      final spans = [
        _span('paragraph text', 72, 700),
        _span('more text', 72, 680),
        _span('even more', 72, 660),
      ];
      final columns = splitter.split(spans, _profile612());
      expect(columns, hasLength(1));
      expect(columns[0], hasLength(3));
    });

    test('2-column: spans di x=72 dan x=320 → 2 kolom, urutan kiri-lalu-kanan',
        () {
      // Kolom kiri (x≈72), Kolom kanan (x≈320)
      // Untuk halaman 612pt: gap di x=195..320 = 125pt gap > 5% of 612 = 30.6pt
      final spans = [
        _span('left col line 1', 72, 700), // kolom kiri
        _span('right col line 1', 320, 700), // kolom kanan (y sama)
        _span('left col line 2', 72, 680), // kolom kiri
        _span('right col line 2', 320, 680), // kolom kanan
      ];
      final columns = splitter.split(spans, _profile612());
      expect(columns, hasLength(2));
      // Kolom 0 = kiri (x < split point)
      expect(columns[0].every((s) => s.xLeft < 250), isTrue);
      // Kolom 1 = kanan (x > split point)
      expect(columns[1].every((s) => s.xLeft >= 250), isTrue);
    });

    test('2-column: reading order kiri dahulu (top→bottom), lalu kanan (top→bottom)',
        () {
      final spans = [
        _span('left-A', 72, 700),
        _span('left-B', 72, 680),
        _span('right-A', 320, 700),
        _span('right-B', 320, 680),
      ];
      final columns = splitter.split(spans, _profile612());
      // columns[0] harus left-A, left-B (sudah diurutkan top→bottom)
      expect(columns[0][0].text, 'left-A');
      expect(columns[0][1].text, 'left-B');
      // columns[1] harus right-A, right-B
      expect(columns[1][0].text, 'right-A');
      expect(columns[1][1].text, 'right-B');
    });

    test('gap terlalu kecil (< 8% pageWidth = 48.96pt) → fallback single-column',
        () {
      // Gap histogram xLeft antara 72 dan 110 = 38pt (< 48.96pt) → single-column
      final spans = [
        _span('text A', 72, 700),
        _span('text B', 110, 700), // xLeft dekat, tidak ada gap besar
      ];
      final columns = splitter.split(spans, _profile612());
      expect(columns, hasLength(1));
    });

    test('profile tanpa pageWidth (pageWidth=0) → selalu single-column', () {
      final noGeomProfile = DocProfile(
        bodyFontSize: 12,
        headingBands: const [],
        totalPages: 1,
        emptyPages: 0,
        pageWidth: 0, // tidak ada info dimensi
        pageHeight: 0,
        bodyLeftMargin: 0,
        bodyRightMargin: 0,
      );
      final spans = [_span('text', 72, 700), _span('other', 350, 700)];
      final columns = splitter.split(spans, noGeomProfile);
      expect(columns, hasLength(1));
    });

    test('spans kosong → return list kosong', () {
      final columns = splitter.split([], _profile612());
      expect(columns, isEmpty);
    });
  });
}
