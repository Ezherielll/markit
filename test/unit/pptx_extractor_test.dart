import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/pptx_extractor.dart';
import 'package:markit/core/output.dart';

import '../helpers/zip_factory.dart';

String _slide(String title, String body, {String? bullets, String? table}) =>
    '<?xml version="1.0" encoding="UTF-8"?>'
    '<p:sld xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main">'
    '<p:cSld><p:spTree>'
    '<p:sp><p:nvSpPr><p:cNvPr id="1" name="Title"/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>'
    '<p:txBody><a:p><a:r><a:t>$title</a:t></a:r></a:p></p:txBody></p:sp>'
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Body"/><p:nvPr/></p:nvSpPr>'
    '<p:txBody><a:p><a:r><a:t>$body</a:t></a:r></a:p>'
    '$bullets</p:txBody></p:sp>'
    '$table'
    '</p:spTree></p:cSld></p:sld>';

Future<String> _run(Map<String, String> entries) async {
  final output = MemoryOutput();
  final result = await const PptxExtractor().extract(
    bytes: buildZip(entries),
    output: output,
  );
  expect(result.itemCount, greaterThan(0));
  return output.content;
}

void main() {
  test('slides → title headings + paragraphs + bullets', () async {
    final md = await _run({
      'ppt/slides/slide1.xml': _slide(
        'Intro',
        'Welcome to the deck.',
        bullets: '<a:p><a:pPr><a:buChar char="&#8226;"/></a:pPr>'
            '<a:r><a:t>Point one</a:t></a:r></a:p>',
      ),
      'ppt/slides/slide2.xml': _slide('Closing', 'Thanks.'),
    });
    expect(md, contains('# Intro'));
    expect(md, contains('Welcome to the deck.'));
    expect(md, contains('- Point one'));
    expect(md, contains('# Closing'));
    expect(md, contains('Thanks.'));
  });

  test('table via graphicFrame → markdown table', () async {
    final table = '<p:graphicFrame><a:graphic><a:graphicData>'
        '<a:tbl><a:tr><a:tc><a:txBody><a:p><a:r><a:t>H1</a:t></a:r></a:p></a:txBody></a:tc>'
        '<a:tc><a:txBody><a:p><a:r><a:t>H2</a:t></a:r></a:p></a:txBody></a:tc></a:tr>'
        '<a:tr><a:tc><a:txBody><a:p><a:r><a:t>1</a:t></a:r></a:p></a:txBody></a:tc>'
        '<a:tc><a:txBody><a:p><a:r><a:t>2</a:t></a:r></a:p></a:txBody></a:tc></a:tr>'
        '</a:tbl></a:graphicData></a:graphic></p:graphicFrame>';
    final md = await _run({
      'ppt/slides/slide1.xml': _slide('Data', 'See table:', table: table),
    });
    expect(md, contains('| H1 | H2 |'));
    expect(md, contains('| 1 | 2 |'));
  });

  test('bold/italic runs', () async {
    final md = await _run({
      'ppt/slides/slide1.xml': _slide(
        'T',
        '',
        bullets: '<a:p><a:r><a:rPr b="1"/><a:t>bold</a:t></a:r>'
            '<a:r><a:rPr i="1"/><a:t>italic</a:t></a:r></a:p>',
      ),
    });
    expect(md, contains('**bold**'));
    expect(md, contains('*italic*'));
  });

  test('no slide entries → corrupt', () async {
    expect(
      () => const PptxExtractor().extract(
        bytes: buildZip({'[Content_Types].xml': '<x/>'}),
        output: MemoryOutput(),
      ),
      throwsA(isA<ConvertException>()),
    );
  });
}
