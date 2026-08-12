import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/paragraph_joiner.dart';
import 'package:markit/models/layout.dart';

Line _line(String text, {double yTop = 100, double h = 12}) {
  final bottom = yTop - h;
  return Line(spans: [
    TextSpan(
      text: text,
      xLeft: 0,
      xRight: text.length * 6.0,
      yBottom: bottom,
      yTop: yTop,
      fontSize: h,
    ),
  ]);
}

void main() {
  final joiner = ParagraphJoiner();
  bool notHeading(Line _) => false;

  group('ParagraphJoiner (FR-04)', () {
    test('gap kecil (baris rapat) → satu paragraf', () {
      // Baris 1: yTop 100..88, baris 2: yTop 85..73 → gap 3
      // Baris 3: yTop 70..58 → gap 3
      final paras = joiner.join(
        [_line('a', yTop: 100), _line('b', yTop: 85), _line('c', yTop: 70)],
        isHeading: notHeading,
      );
      expect(paras, hasLength(1));
      expect(paras.first.map((l) => l.text).toList(), ['a', 'b', 'c']);
    });

    test('gap besar (spasi paragraf) → terpisah', () {
      // Baris rapat 100/85/70 (gap 3,3), lalu lompat besar ke yTop 40
      // (gap 18) → median 3, threshold 4.5 → 18 memutus paragraf.
      final paras = joiner.join(
        [
          _line('a', yTop: 100),
          _line('b', yTop: 85),
          _line('c', yTop: 70),
          _line('d', yTop: 40),
        ],
        isHeading: notHeading,
      );
      expect(paras, hasLength(2));
      expect(paras[0].map((l) => l.text).toList(), ['a', 'b', 'c']);
      expect(paras[1].single.text, 'd');
    });

    test('heading memutus paragraf', () {
      final paras = joiner.join(
        [
          _line('para one line', yTop: 100),
          _line('Chapter 1', yTop: 80, h: 18),
          _line('para two', yTop: 55),
        ],
        isHeading: (l) => l.text == 'Chapter 1',
      );
      expect(paras, hasLength(3));
      expect(paras[1].single.text, 'Chapter 1');
    });

    test('hanya satu baris → satu paragraf', () {
      final paras = joiner.join([_line('solo')], isHeading: notHeading);
      expect(paras, hasLength(1));
    });
  });

  group('Hyphenation de-joining (Fase C)', () {
    // Helper: baris satu span dengan posisi X eksplisit — kedua fragmen
    // terhifen sengaja diberi gap X nyata (mis. xRight=100 vs xLeft=200)
    // supaya test benar-benar memverifikasi tidak ada spasi yang disisipkan.
    Line gapLine(String text, double xLeft, double xRight,
        {double yTop = 100}) {
      return Line(spans: [
        TextSpan(
          text: text,
          xLeft: xLeft,
          xRight: xRight,
          yBottom: yTop - 12,
          yTop: yTop,
          fontSize: 12,
        ),
      ]);
    }

    test('baris berakhir "-" + huruf kecil berikutnya → gabung tanpa "-"', () {
      // "docu-" (xRight 100) + "ment continues" (xLeft 200) → satu baris
      // 'document continues' — tanpa spasi di antara kedua fragmen.
      final paras = joiner.join(
        [gapLine('docu-', 40, 100), gapLine('ment continues', 200, 320, yTop: 85)],
        isHeading: notHeading,
      );
      final allText = paras.expand((p) => p).map((l) => l.text).join('');
      expect(paras.single.single.text, 'document continues');
      expect(allText.contains('document'), isTrue);
      expect(allText.contains('-m'), isFalse);
      expect(allText.contains('docu ment'), isFalse);
    });

    test('baris berakhir "-" + KAPITAL → tidak digabung', () {
      // "Smith-" + "Jones" → tetap terpisah (tidak ada merge hiphenasi):
      // dua paragraf, masing-masing satu baris utuh.
      final paras = joiner.join(
        [gapLine('Smith-', 40, 100), gapLine('Jones', 200, 300, yTop: 85)],
        isHeading: notHeading,
      );
      expect(paras, hasLength(2));
      expect(paras[0].single.text, 'Smith-');
      expect(paras[1].single.text, 'Jones');
      expect(paras[0].single.text, isNot(contains('Smith-Jones')));
    });

    test('baris berakhir "-" + angka → tidak digabung ("5-" + "10")', () {
      final paras = joiner.join(
        [gapLine('5-', 40, 60), gapLine('10', 200, 240, yTop: 85)],
        isHeading: notHeading,
      );
      expect(paras, hasLength(2));
      expect(paras[0].single.text, '5-');
      expect(paras[1].single.text, '10');
      expect(paras[0].single.text, isNot(contains('5-10')));
    });
  });
}
