import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/core/markdown_writer.dart';
import 'package:pdflow/models/layout.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdflow_md_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  test('blok heading/paragraf/list → markdown valid, blank line antar blok',
      () async {
    final file = File('${tmp.path}/out.md');
    final sink = file.openWrite();
    final w = MarkdownWriter(sink);
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
    await sink.flush();
    await sink.close();

    final bytes = await file.readAsBytes();
    final text = utf8.decode(bytes);
    expect(text, '# Chapter 1\n\nFirst paragraph text.\n\n- Item one\n');

    // D8: UTF-8 tanpa BOM, tidak ada \r\n.
    expect(bytes.sublist(0, 3), [0x23, 0x20, 0x43]); // "# C" — bukan BOM
    expect(text.contains('\r\n'), isFalse);
  });

  test('heading level 2 → ##', () async {
    final file = File('${tmp.path}/out2.md');
    final w = MarkdownWriter(file.openWrite());
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
    final w = MarkdownWriter(file.openWrite());
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
    final w = MarkdownWriter(file.openWrite());
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['a']));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['b']));
    w.writeBlock(Block(type: BlockType.paragraph, lines: const ['c']));
    await w.close();
    expect(await file.readAsString(), 'a\n\nb\n\nc\n');
  });
}
