import 'package:flutter_test/flutter_test.dart';
import 'package:markit/models/layout.dart';

void main() {
  group('Block model extensions (Fase C)', () {
    test('Block default: listDepth=0, cells=null', () {
      final block = Block(type: BlockType.paragraph, lines: ['teks']);
      expect(block.listDepth, 0);
      expect(block.cells, isNull);
    });

    test('Block listDepth=1 untuk nested list item', () {
      final block = Block(
        type: BlockType.listItem,
        lines: ['nested item'],
        listDepth: 1,
      );
      expect(block.listDepth, 1);
    });

    test('Block tableRow dengan cells', () {
      final block = Block(
        type: BlockType.tableRow,
        lines: ['Name | Qty | Price'],
        cells: ['Name', 'Qty', 'Price'],
      );
      expect(block.type, BlockType.tableRow);
      expect(block.cells, ['Name', 'Qty', 'Price']);
    });

    test('Block tableHeader dengan cells', () {
      final block = Block(
        type: BlockType.tableHeader,
        lines: ['Name | Qty | Price'],
        cells: ['Name', 'Qty', 'Price'],
      );
      expect(block.type, BlockType.tableHeader);
    });

    test('BlockType enum memiliki tableRow dan tableHeader', () {
      expect(BlockType.values, contains(BlockType.tableRow));
      expect(BlockType.values, contains(BlockType.tableHeader));
    });
  });

  group('normalizeTextSpanBounds (regresi xLeft<=xRight)', () {
    test('bounds normal → tidak berubah', () {
      final b = normalizeTextSpanBounds(
        left: 10, right: 20, bottom: 5, top: 15,
      );
      expect(b.xLeft, 10);
      expect(b.xRight, 20);
      expect(b.yBottom, 5);
      expect(b.yTop, 15);
    });

    test('x terflip (left > right) → ditukar', () {
      final b = normalizeTextSpanBounds(
        left: 20, right: 10, bottom: 5, top: 15,
      );
      expect(b.xLeft, 10);
      expect(b.xRight, 20);
    });

    test('y terflip (bottom > top) → ditukar', () {
      final b = normalizeTextSpanBounds(
        left: 10, right: 20, bottom: 15, top: 5,
      );
      expect(b.yBottom, 5);
      expect(b.yTop, 15);
    });

    test('hasil normalize lolos assert TextSpan (debug)', () {
      final b = normalizeTextSpanBounds(
        left: 20, right: 10, bottom: 15, top: 5,
      );
      expect(
        () => TextSpan(
          text: 'x',
          xLeft: b.xLeft,
          xRight: b.xRight,
          yBottom: b.yBottom,
          yTop: b.yTop,
          fontSize: 10,
        ),
        returnsNormally,
      );
    });
  });

  group('Block alignments (Fase D)', () {
    test('Block default: alignments null', () {
      final block = Block(type: BlockType.tableRow, lines: ['a | b'], cells: ['a', 'b']);
      expect(block.alignments, isNull);
    });

    test('Block tableRow dengan alignments', () {
      final block = Block(
        type: BlockType.tableRow,
        lines: ['a | b'],
        cells: ['a', 'b'],
        alignments: const ['left', 'center'],
      );
      expect(block.alignments, ['left', 'center']);
    });
  });
}
