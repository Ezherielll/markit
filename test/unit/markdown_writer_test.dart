import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/markdown_writer.dart';
import 'package:markit/core/output.dart';
import 'package:markit/models/layout.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_md_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('blok heading/paragraf/list → markdown valid, blank line antar blok',
      () async {
    final file = File('${tmp.path}/out.md');
    final w = MarkdownWriter(FileMdSink(file.openWrite()));
    w.writeBlock(Block(
      type: BlockType.heading,
      lines: const ['Chapter 1'],
      headingLevel: 1,
    ));
    w.writeBlock(Block(
      type: BlockType.paragraph,
      lines: const ['First paragraph text.'],
    ));
    w.writeBlock(Block(
      type: BlockType.listItem,
      lines: const ['Item one'],
    ));
    await w.flush();
    await w.close();

    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes);
    expect(text, '# Chapter 1\n\nFirst paragraph text.\n\n- Item one\n');

    // D8: UTF-8 tanpa BOM, tidak ada \r\n.
    expect(bytes.sublist(0, 3), [0x23, 0x20, 0x43]); // "# C" — bukan BOM
    expect(text.contains('\r\n'), isFalse);
  });

  test('heading level 2 → ##', () async {
    final file = File('${tmp.path}/out2.md');
    final w = MarkdownWriter(FileMdSink(file.openWrite()));
    w.writeBlock(Block(
      type: BlockType.heading,
      lines: const ['Sub'],
      headingLevel: 2,
    ));
    await w.close();
    expect(await file.readAsString(), '## Sub\n');
  });

  test('escaping: teks diawali # atau - tidak jadi struktur', () async {
    final file = File('${tmp.path}/out3.md');
    final w = MarkdownWriter(FileMdSink(file.openWrite()));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['# not heading']));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['- not list']));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['3. not ordered']));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['a`b']));
    await w.close();

    final s = await file.readAsString();
    expect(s, contains(r'\# not heading'));
    expect(s, contains(r'\- not list'));
    expect(s, contains(r'\3. not ordered'));
    expect(s, contains(r'a\`b'));
  });

  test('streaming: writeBlock bertahap tetap konsisten', () async {
    final file = File('${tmp.path}/out4.md');
    final w = MarkdownWriter(FileMdSink(file.openWrite()));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['a']));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['b']));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['c']));
    await w.close();
    expect(await file.readAsString(), 'a\n\nb\n\nc\n');
  });

  test('MemoryMdSink: menulis ke StringBuffer (web)', () async {
    final buffer = StringBuffer();
    final w = MarkdownWriter(MemoryMdSink(buffer));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['web output']));
    await w.close();
    expect(buffer.toString(), 'web output\n');
  });

  group('Fase A: ordered/unordered list rendering', () {
    test('orderedListItem → "N. text" sesuai listIndex', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.orderedListItem,
        lines: const ['Buy apples'],
        listIndex: 1,
      ));
      w.writeBlock(Block(
        type: BlockType.orderedListItem,
        lines: const ['Buy bananas'],
        listIndex: 2,
      ));
      await w.close();
      expect(buffer.toString(), '1. Buy apples\n\n2. Buy bananas\n');
    });

    test('orderedListItem tanpa listIndex → fallback 1', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.orderedListItem,
        lines: const ['Alpha'],
      ));
      await w.close();
      expect(buffer.toString(), '1. Alpha\n');
    });

    test('unorderedListItem → "- text"', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.unorderedListItem,
        lines: const ['Item one'],
      ));
      await w.close();
      expect(buffer.toString(), '- Item one\n');
    });
  });

  group('MarkdownWriter Fase C', () {
    test('tableHeader → baris header + separator', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.tableHeader,
        lines: const ['Name | Qty | Price'],
        cells: const ['Name', 'Qty', 'Price'],
      ));
      await w.close();
      expect(buffer.toString(), '| Name | Qty | Price |\n| --- | --- | --- |\n');
    });

    test('tableRow → baris tabel tanpa separator', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.tableRow,
        lines: const ['Apples | 10 | 2.50'],
        cells: const ['Apples', '10', '2.50'],
      ));
      await w.close();
      expect(buffer.toString(), '| Apples | 10 | 2.50 |\n');
      expect(buffer.toString(), isNot(contains('---')));
    });

    test('tableHeader + tableRow berurutan → tidak ada blank line di antara',
        () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.tableHeader,
        lines: const ['Name | Qty'],
        cells: const ['Name', 'Qty'],
      ));
      w.writeBlock(Block(
        type: BlockType.tableRow,
        lines: const ['Apples | 10'],
        cells: const ['Apples', '10'],
      ));
      await w.close();
      expect(buffer.toString(), '| Name | Qty |\n| --- | --- |\n| Apples | 10 |\n');
    });

    test('setelah tabel selesai → blank line sebelum blok berikutnya',
        () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.tableHeader,
        lines: const ['Name'],
        cells: const ['Name'],
      ));
      w.writeBlock(Block(
        type: BlockType.tableRow,
        lines: const ['Apples'],
        cells: const ['Apples'],
      ));
      w.writeBlock(Block(
        type: BlockType.paragraph,
        lines: const ['Setelah tabel.'],
      ));
      await w.close();
      expect(
        buffer.toString(),
        '| Name |\n| --- |\n| Apples |\n\nSetelah tabel.\n',
      );
    });

    test('listItem depth=0 → "- item"', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(type: BlockType.listItem, lines: const ['flat item']));
      await w.close();
      expect(buffer.toString(), contains('- flat item'));
      expect(buffer.toString(), isNot(contains('  -')));
    });

    test('listItem depth=1 → "  - nested item"', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.listItem,
        lines: const ['nested item'],
        listDepth: 1,
      ));
      await w.close();
      expect(buffer.toString(), contains('  - nested item'));
    });

    test('orderedListItem depth=1 → indent 2 spasi + nomor', () async {
      final buffer = StringBuffer();
      final w = MarkdownWriter(MemoryMdSink(buffer));
      w.writeBlock(Block(
        type: BlockType.orderedListItem,
        lines: const ['sub step'],
        listDepth: 1,
        listIndex: 2,
      ));
      await w.close();
      expect(buffer.toString(), '  2. sub step\n');
    });
  });
}
