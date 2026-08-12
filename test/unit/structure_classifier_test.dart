import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/doc_stats.dart';
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

DocProfile _profileWith(Map<double, int> hist) =>
    DocProfile.fromHistogram(hist, totalPages: 1);

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
      expect(blocks[0].type, BlockType.unorderedListItem);
      expect(blocks[0].text, 'Item one');
      expect(blocks[1].type, BlockType.unorderedListItem);
      expect(blocks[2].type, BlockType.unorderedListItem);
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
      expect(blocks[0].type, BlockType.unorderedListItem);
      expect(blocks[0].text, 'Item one');
      expect(blocks[1].type, BlockType.unorderedListItem);
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
      expect(blocks.single.type, BlockType.unorderedListItem);
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

  group('StructureClassifier multi-level heading (Fase A)', () {
    test('band H1/H2/H3 → heading level sesuai band, body tetap paragraph', () {
      final profile = _profileWith({12.0: 100, 14.0: 4, 16.0: 3, 20.0: 2});
      final c = StructureClassifier.withProfile(profile: profile);
      final blocks = c.classify(_paras([
        [('Chapter', 20.0)],
        [('Section', 16.0)],
        [('Subsection', 14.0)],
        [('Body text.', 12.0)],
      ]));
      expect(blocks[0].type, BlockType.heading);
      expect(blocks[0].headingLevel, 1);
      expect(blocks[1].type, BlockType.heading);
      expect(blocks[1].headingLevel, 2);
      expect(blocks[2].type, BlockType.heading);
      expect(blocks[2].headingLevel, 3);
      expect(blocks[3].type, BlockType.paragraph);
    });

    test('size di luar band tapi >= 1.2x body → fallback heading level 1', () {
      final profile = _profileWith({12.0: 100, 20.0: 2});
      final c = StructureClassifier.withProfile(profile: profile);
      final blocks = c.classify(_paras([
        [('In-between size', 18.0)], // 18 >= 12 * 1.2, tidak di band mana pun
      ]));
      expect(blocks.single.type, BlockType.heading);
      expect(blocks.single.headingLevel, 1);
    });

    test('tanpa profile → faktor legacy, level selalu 1', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [('Big title', 24.0)],
      ]));
      expect(blocks[0].type, BlockType.heading);
      expect(blocks[0].headingLevel, 1);
    });
  });

  group('List detection pattern-based (Fase A)', () {
    test("karakter 'o' bukan bullet (false positive lama)", () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [('of the system', 12.0)],
      ]));
      expect(blocks.single.type, BlockType.paragraph);
    });

    test("'-' tanpa spasi bukan bullet (mis. '-3°C')", () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [('-3°C temperature', 12.0)],
        [('- item', 12.0)],
      ]));
      expect(blocks[0].type, BlockType.paragraph);
      expect(blocks[1].type, BlockType.unorderedListItem);
    });

    test('ordered list 1. 2. 3. → orderedListItem dengan listIndex', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [
          ('1. First', 12.0),
          ('2. Second', 12.0),
          ('3. Third', 12.0),
        ],
      ]));
      expect(blocks, hasLength(3));
      expect(blocks[0].type, BlockType.orderedListItem);
      expect(blocks[0].text, 'First');
      expect(blocks[0].listIndex, 1);
      expect(blocks[1].listIndex, 2);
      expect(blocks[2].listIndex, 3);
    });

    test('ordered list dengan ")" (mis. "1) item") → orderedListItem', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [
          ('1) First', 12.0),
          ('2) Second', 12.0),
        ],
      ]));
      expect(blocks[0].type, BlockType.orderedListItem);
      expect(blocks[0].text, 'First');
      expect(blocks[0].listIndex, 1);
    });

    test('ordered list huruf (a. b.) → orderedListItem, listIndex null', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [
          ('a. Alpha', 12.0),
          ('b. Beta', 12.0),
        ],
      ]));
      expect(blocks[0].type, BlockType.orderedListItem);
      expect(blocks[0].text, 'Alpha');
      expect(blocks[0].listIndex, isNull);
    });

    test('baris lanjutan ordered item menyambung, bukan item baru', () {
      final c = StructureClassifier(bodyFontSize: 12);
      final blocks = c.classify(_paras([
        [
          ('1. Long item', 12.0),
          ('continues here', 12.0),
        ],
      ]));
      expect(blocks.single.type, BlockType.orderedListItem);
      expect(blocks.single.lines, ['Long item', 'continues here']);
      expect(blocks.single.listIndex, 1);
    });
  });
}
