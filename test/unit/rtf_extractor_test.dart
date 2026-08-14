import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/rtf_extractor.dart';
import 'package:markit/core/output.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Future<String> _run(Uint8List bytes) async {
  final output = MemoryOutput();
  final result = await const RtfExtractor().extract(
    bytes: bytes,
    output: output,
  );
  expect(result.itemCount, greaterThan(0));
  return output.content;
}

void main() {
  test('paragraphs with bold/italic emphasis', () async {
    final md = await _run(_utf8(r'{\rtf1\ansi Hello {\b bold} and {\i italic}.\par Second paragraph.}'));
    expect(md, contains('Hello **bold** and *italic*.'));
    expect(md, contains('Second paragraph.'));
  });

  test('unicode \\uN + hex escapes', () async {
    final md = await _run(_utf8(r'{\rtf1\ansi caf\u233?' '\\' r"'e9 and \'e9}"));
    expect(md, contains('café'));
    expect(md, isNot(contains('?')));
  });

  test('combined bold+italic group produces ***text***', () async {
    final md = await _run(_utf8(r'{\rtf1\ansi{\b\i text}}'));
    expect(md, contains('***text***'));
  });

  test('nested emphasis closes inner group before outer', () async {
    final md = await _run(_utf8(r'{\rtf1\ansi{\b A {\i B} C}}'));
    expect(md, contains('**A *B* C**'));
    expect(md, isNot(contains('***')));
  });

  test('font table and destinations skipped', () async {
    final md = await _run(_utf8(
      r'{\rtf1\ansi{\fonttbl{\f0 Arial;}{\f1 Times;}}'
      r'{\info{\title Fake Title}}'
      r'Real body text.\par'
      r'{\*\generator FakeGen}Trailing.'
      r'{\*\bkmkstart B1}End.}',
    ));
    expect(md, isNot(contains('Arial')));
    expect(md, isNot(contains('Fake Title')));
    expect(md, isNot(contains('FakeGen')));
    expect(md, isNot(contains('bkmkstart')));
    expect(md, isNot(contains('B1')));
    expect(md, contains('Real body text.'));
    expect(md, contains('Trailing.'));
    expect(md, contains('End.'));
  });

  test('bullet paragraphs become list items', () async {
    final md = await _run(_utf8(r'{\rtf1\ansi{\pntext\f0\' r"95\tab}" r'\bullet Item one\par\bullet Item two\par}'));
    expect(md, contains('- Item one'));
    expect(md, contains('- Item two'));
    expect(md, isNot(contains(r'\-')));
  });

  test('not rtf (random bytes) → corrupt', () async {
    expect(
      () => const RtfExtractor().extract(
        bytes: Uint8List.fromList([1, 2, 3]),
        output: MemoryOutput(),
      ),
      throwsA(isA<ConvertException>()),
    );
  });
}
