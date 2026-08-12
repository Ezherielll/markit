import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/doc_stats.dart';
import 'package:markit/core/table_detector.dart';
import 'package:markit/models/layout.dart';

// Buat satu baris (paragraf = satu baris) dengan spans di posisi tertentu
List<Line> _row(List<(String text, double x)> cells, {double y = 700, double h = 12}) {
  return [
    Line(
      spans: cells
          .map((c) => TextSpan(
                text: c.$1,
                xLeft: c.$2,
                xRight: c.$2 + c.$1.length * 6.0,
                yBottom: y - h,
                yTop: y,
                fontSize: h,
              ))
          .toList(),
    ),
  ];
}

DocProfile _profileWith({double bodyLeft = 72}) => DocProfile(
      bodyFontSize: 12,
      headingBands: const [],
      totalPages: 1,
      emptyPages: 0,
      pageWidth: 612,
      pageHeight: 792,
      bodyLeftMargin: bodyLeft,
      bodyRightMargin: 540,
    );

void main() {
  group('TableDetector', () {
    final detector = TableDetector();

    test('3 baris tabel konsisten → isTable=true', () {
      final paragraphs = [
        _row([('Name', 72), ('Qty', 200), ('Price', 350)], y: 700),
        _row([('Apples', 72), ('10', 200), ('2.50', 350)], y: 675),
        _row([('Bananas', 72), ('20', 200), ('1.75', 350)], y: 650),
      ];
      final tagged = detector.tag(paragraphs, _profileWith());
      expect(tagged, hasLength(1));
      expect(tagged[0].$2, isTrue); // isTable = true
    });

    test('kurang dari 3 baris → bukan tabel', () {
      final paragraphs = [
        _row([('Name', 72), ('Qty', 200)], y: 700),
        _row([('Apples', 72), ('10', 200)], y: 675),
      ];
      final tagged = detector.tag(paragraphs, _profileWith());
      expect(tagged.every((g) => !g.$2), isTrue);
    });

    test('gap posisi tidak konsisten (variance >= 20pt) → bukan tabel', () {
      // Catatan tuning: plan awal memakai ambang 10pt, dinaikkan ke 20pt
      // (maxGapVariancePt) karena lebar karakter sintetis (6pt/char) membuat
      // variance X-gap mudah melewati 10pt pada data non-tabel biasa.
      final paragraphs = [
        _row([('A', 72), ('B', 200)], y: 700),
        _row([('C', 72), ('D', 220)], y: 675),
        _row([('E', 72), ('F', 180)], y: 650),
      ];
      final tagged = detector.tag(paragraphs, _profileWith());
      expect(tagged.every((g) => !g.$2), isTrue);
    });

    test('tabel diikuti paragraf biasa → dua group terpisah', () {
      final paragraphs = [
        _row([('Name', 72), ('Val', 200)], y: 700),
        _row([('A', 72), ('1', 200)], y: 675),
        _row([('B', 72), ('2', 200)], y: 650),
        [Line(spans: [
          TextSpan(
            text: 'Normal paragraph text.',
            xLeft: 72, xRight: 400,
            yBottom: 610, yTop: 622,
            fontSize: 12,
          ),
        ])],
      ];
      final tagged = detector.tag(paragraphs, _profileWith());
      expect(tagged, hasLength(2));
      expect(tagged[0].$2, isTrue);   // tabel
      expect(tagged[1].$2, isFalse);  // paragraf biasa
    });

    test('paragraphs kosong → return kosong', () {
      final tagged = detector.tag([], _profileWith());
      expect(tagged, isEmpty);
    });
  });
}
