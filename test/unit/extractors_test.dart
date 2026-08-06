import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/csv_extractor.dart';
import 'package:markit/core/extractors/html_extractor.dart';
import 'package:markit/core/extractors/json_extractor.dart';
import 'package:markit/core/extractors/text_extractor.dart';
import 'package:markit/core/extractors/xml_extractor.dart';
import 'package:markit/core/markdown_writer.dart';
import 'package:markit/core/output.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Future<String> _run(
  Object extractor,
  Uint8List bytes, {
  String name = 'input',
}) async {
  final output = MemoryOutput();
  final sink = await output.openSink();
  final writer = MarkdownWriter(sink);
  final result = await _extract(extractor, bytes, writer);
  await writer.close();
  await output.commit();
  expect(result, isNotNull);
  return output.content;
}

Future<dynamic> _extract(
  Object extractor,
  Uint8List bytes,
  MarkdownWriter writer,
) {
  return switch (extractor) {
    TextExtractor() => extractor.extract(bytes: bytes, writer: writer),
    CsvExtractor() => extractor.extract(bytes: bytes, writer: writer),
    JsonExtractor() => extractor.extract(bytes: bytes, writer: writer),
    XmlExtractor() => extractor.extract(bytes: bytes, writer: writer),
    HtmlExtractor() => extractor.extract(bytes: bytes, writer: writer),
    _ => throw UnsupportedError('unreachable'),
  };
}

void main() {
  group('TextExtractor', () {
    test('plain text → paragraf dipisah baris kosong', () async {
      final md = await _run(
        const TextExtractor(),
        _utf8('Hello world.\n\nSecond paragraph.\n\nThird.'),
      );
      expect(
        md,
        'Hello world.\n\nSecond paragraph.\n\nThird.\n',
      );
    });

    test('markdown passthrough (# heading)', () async {
      final md = await _run(
        const TextExtractor(),
        _utf8('# Title\n\nSome body text.'),
        name: 'notes.md',
      );
      expect(md, contains('# Title'));
    });

    test('BOM di-strip', () async {
      final md = await _run(
        const TextExtractor(),
        Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Hello.')]),
      );
      expect(md, startsWith('Hello.'));
    });

    test('latin1 fallback tidak error', () async {
      final md = await _run(
        const TextExtractor(),
        Uint8List.fromList([0xE9, 0x20, 0x2E, 0x2E, 0x2E]), // é ... (latin1)
      );
      expect(md, isNotEmpty);
    });

    test('file kosong → itemCount 0', () async {
      final output = MemoryOutput();
      final sink = await output.openSink();
      final writer = MarkdownWriter(sink);
      final result = await const TextExtractor().extract(
        bytes: _utf8('   \n  '),
        writer: writer,
      );
      expect(result.itemCount, 0);
    });
  });

  group('CsvExtractor', () {
    test('header + rows → tabel markdown', () async {
      final md = await _run(
        const CsvExtractor(),
        _utf8('Name,Age\nAlice,30\nBob,25'),
      );
      expect(
        md,
        contains('| Name | Age |\n| --- | --- |\n| Alice | 30 |\n| Bob | 25 |'),
      );
    });

    test('quoted field dengan koma', () async {
      final md = await _run(
        const CsvExtractor(),
        _utf8('A,B\n"x,y",z'),
      );
      expect(md, contains('| x,y | z |'));
    });

    test('CRLF + baris kosong dilewati', () async {
      final md = await _run(
        const CsvExtractor(),
        _utf8('A,B\r\n1,2\r\n\r\n3,4'),
      );
      expect(md, contains('| 1 | 2 |'));
      expect(md, contains('| 3 | 4 |'));
    });

    test('empty → ConvertException noText', () async {
      expect(
        () => _run(const CsvExtractor(), _utf8('')),
        throwsA(isA<ConvertException>()),
      );
    });
  });

  group('JsonExtractor', () {
    test('pretty-print ke code block', () async {
      final md = await _run(
        const JsonExtractor(),
        _utf8('{"a":1,"b":[2,3]}'),
      );
      expect(md, contains('```json'));
      expect(md, contains('"a": 1'));
      expect(md, contains('"b": ['));
    });

    test('invalid JSON → ConvertException corrupt', () async {
      expect(
        () => _run(const JsonExtractor(), _utf8('{invalid')),
        throwsA(isA<ConvertException>()),
      );
    });
  });

  group('XmlExtractor', () {
    test('indented ke code block', () async {
      final md = await _run(
        const XmlExtractor(),
        _utf8('<root><a>1</a><b><c>2</c></b></root>'),
      );
      expect(md, contains('```xml'));
      expect(md, contains('<a>1</a>'));
      expect(md, contains('  <c>2</c>'));
    });

    test('invalid XML → ConvertException corrupt', () async {
      expect(
        () => _run(const XmlExtractor(), _utf8('<root><a></root>')),
        throwsA(isA<ConvertException>()),
      );
    });
  });

  group('HtmlExtractor', () {
    test('heading + paragraf + list', () async {
      final md = await _run(
        const HtmlExtractor(),
        _utf8(
          '<html><body>'
          '<h1>Title</h1>'
          '<p>Hello <strong>world</strong>.</p>'
          '<ul><li>One</li><li>Two</li></ul>'
          '</body></html>',
        ),
      );
      expect(md, contains('# Title'));
      expect(md, contains('Hello **world**.'));
      expect(md, contains('- One'));
      expect(md, contains('- Two'));
    });

    test('tabel → tabel markdown', () async {
      final md = await _run(
        const HtmlExtractor(),
        _utf8(
          '<table><tr><th>A</th><th>B</th></tr>'
          '<tr><td>1</td><td>2</td></tr></table>',
        ),
      );
      expect(md, contains('| A | B |'));
      expect(md, contains('| 1 | 2 |'));
    });

    test('link → teks (URL)', () async {
      final md = await _run(
        const HtmlExtractor(),
        _utf8('<p>See <a href="https://example.com">docs</a>.</p>'),
      );
      expect(md, contains('docs (https://example.com)'));
    });

    test('no structure → fallback satu blok teks', () async {
      final md = await _run(
        const HtmlExtractor(),
        _utf8('<html><body>Just plain text here.</body></html>'),
      );
      expect(md, contains('Just plain text here.'));
    });
  });
}
