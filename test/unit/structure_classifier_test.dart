import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/structure_classifier.dart';
import 'package:markit/models/layout.dart';

List<List<Line>> _paras(List<List<(String, double)>> raw) {
  return [
    for (final plines in raw)
      [
        for (final (text, h) in plines)
          Line(spans: [
            TextSpan(
              text: text,
              xLeft: 0,
              xRight: text.length * 6.0,
              yBottom: 0,
              yTop: h,
              fontSize: h,
            ),
          ]),
      ],
  ];
}

void main() {
  group('StructureClassifier (FR-05/06)', () {
    test('heading vs body via bodyFontSize stats (bukan hardcode)', () {
      // body = 12 → heading threshold = 12 * 1.2 = 14.4
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [('Chapter 1', 24.0)],
        [('Plain paragraph text.', 12.0)],
      ]));
      expect(blocks, hasLength(2));
      expect(blocks[0].type, BlockType.heading);
      expect(blocks[0].headingLevel, 1);
      expect(blocks[1].type, BlockType.paragraph);
    });

    test('heading multi-line → satu blok heading', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [('Chapter', 18.0), (' One', 18.0)],
      ]));
      expect(blocks.single.type, BlockType.heading);
      expect(blocks.single.text, 'Chapter One');
    });

    test('list bullet: •, -, *', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [('• Item one', 12.0)],
        [('- Item two', 12.0)],
        [('* Item three', 12.0)],
        [('Normal paragraph', 12.0)],
      ]));
      expect(blocks[0].type, BlockType.listItem);
      expect(blocks[0].text, 'Item one');
      expect(blocks[1].type, BlockType.listItem);
      expect(blocks[2].type, BlockType.listItem);
      expect(blocks[3].type, BlockType.paragraph);
    });

    test('dua item bullet dalam satu paragraf → dua listItem terpisah', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [
          ('• Item one', 12.0),
          ('• Item two', 12.0),
        ],
      ]));
      expect(blocks, hasLength(2));
      expect(blocks[0].type, BlockType.listItem);
      expect(blocks[0].text, 'Item one');
      expect(blocks[1].type, BlockType.listItem);
      expect(blocks[1].text, 'Item two');
    });

    test('baris lanjutan list item ikut dalam item', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [
          ('• Long item', 12.0),
          ('continues here', 12.0),
        ],
      ]));
      expect(blocks.single.type, BlockType.listItem);
      expect(blocks.single.lines, ['Long item', 'continues here']);
    });

    test('bodyFontSize 0 (no text) → semua jadi paragraph, tidak crash', () {
      final c = StructureClassifier(bodyFontSize: 0);
      final blocks = c.classify(_paras([
        [('Big line', 40.0)],
      ]));
      expect(blocks.single.type, BlockType.paragraph);
    });

    test('sedikit di atas body (mis. 13 vs 12) bukan heading (1.2x)', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [('Almost heading', 13.0)],
      ]));
      expect(blocks.single.type, BlockType.paragraph);
    });
  });
}
