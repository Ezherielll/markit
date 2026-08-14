import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/odf_extractor.dart';
import 'package:markit/core/output.dart';

import '../helpers/zip_factory.dart';

String _content(String body) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0">'
    '<office:body>$body</office:body></office:document-content>';

Future<String> _run(String contentXml) async {
  final output = MemoryOutput();
  final result = await const OdfExtractor().extract(
    bytes: buildZip({'content.xml': contentXml}),
    output: output,
  );
  expect(result.itemCount, greaterThan(0));
  return output.content;
}

void main() {
  test('odt: headings + paragraphs + list + table', () async {
    final md = await _run(_content(
      '<office:text>'
      '<text:h text:outline-level="1">Chapter One</text:h>'
      '<text:p>First paragraph.</text:p>'
      '<text:list><text:list-item><text:p>Alpha</text:p></text:list-item>'
      '<text:list-item><text:p>Beta</text:p></text:list-item></text:list>'
      '<table:table table:name="T"><table:table-row>'
      '<table:table-cell office:value-type="string"><text:p>A</text:p></table:table-cell>'
      '<table:table-cell office:value-type="string"><text:p>B</text:p></table:table-cell>'
      '</table:table-row><table:table-row>'
      '<table:table-cell office:value-type="string"><text:p>1</text:p></table:table-cell>'
      '<table:table-cell office:value-type="string"><text:p>2</text:p></table:table-cell>'
      '</table:table-row></table:table>'
      '</office:text>',
    ));
    expect(md, contains('# Chapter One'));
    expect(md, contains('First paragraph.'));
    expect(md, contains('- Alpha'));
    expect(md, contains('| A | B |'));
    expect(md, contains('| 1 | 2 |'));
  });

  test('odp: draw:page → slide headings', () async {
    final md = await _run(_content(
      '<office:presentation>'
      '<draw:page draw:name="Slide 1"><text:p>Welcome text.</text:p></draw:page>'
      '<draw:page draw:name="Slide 2"><text:p>Second slide.</text:p></draw:page>'
      '</office:presentation>',
    ));
    expect(md, contains('# Slide 1'));
    expect(md, contains('Welcome text.'));
    expect(md, contains('# Slide 2'));
  });

  test('ods: spreadsheet tables', () async {
    final md = await _run(_content(
      '<office:spreadsheet>'
      '<table:table table:name="Sheet1"><table:table-row>'
      '<table:table-cell office:value-type="string"><text:p>H1</text:p></table:table-cell>'
      '<table:table-cell office:value-type="string"><text:p>H2</text:p></table:table-cell>'
      '</table:table-row></table:table>'
      '</office:spreadsheet>',
    ));
    expect(md, contains('# Sheet1'));
    expect(md, contains('| H1 | H2 |'));
  });

  test('notes and tracked changes are skipped', () async {
    final md = await _run(_content(
      '<office:text>'
      '<text:p>Visible.</text:p>'
      '<office:annotation><text:p>Hidden note</text:p></office:annotation>'
      '<text:tracked-changes><text:changed-region><text:insertion>'
      '<office:change-track-change/><text:p>Hidden change</text:p>'
      '</text:insertion></text:changed-region></text:tracked-changes>'
      '</office:text>',
    ));
    expect(md, contains('Visible.'));
    expect(md, isNot(contains('Hidden')));
  });

  test('not a zip / missing content.xml → corrupt', () async {
    expect(
      () => const OdfExtractor().extract(
        bytes: buildZip({'other.xml': '<x/>'}),
        output: MemoryOutput(),
      ),
      throwsA(isA<ConvertException>()),
    );
  });
}
