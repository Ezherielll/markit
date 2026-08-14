import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/xlsx_extractor.dart';
import 'package:markit/core/output.dart';

import '../helpers/zip_factory.dart';

Future<String> _run(Map<String, String> entries) async {
  final output = MemoryOutput();
  final result = await const XlsxExtractor().extract(
    bytes: buildZip(entries),
    output: output,
  );
  expect(result.itemCount, greaterThan(0));
  return output.content;
}

const _contentTypes = '[Content_Types].xml';

void main() {
  test('shared strings + numbers + sheet heading', () async {
    final md = await _run({
      _contentTypes: '<x/>',
      'xl/workbook.xml': '<?xml version="1.0"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="Data" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<?xml version="1.0"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/sharedStrings.xml': '<?xml version="1.0"?>'
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<si><t>Name</t></si><si><t>Age</t></si><si><t>Alice</t></si></sst>',
      'xl/worksheets/sheet1.xml': '<?xml version="1.0"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData><row r="1"><c r="A1" t="s"><v>0</v></c>'
          '<c r="B1" t="s"><v>1</v></c></row>'
          '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>30</v></c></row>'
          '</sheetData></worksheet>',
    });
    expect(md, contains('# Data'));
    expect(md, contains('| Name | Age |'));
    expect(md, contains('| Alice | 30 |'));
  });

  test('inline strings + sparse row padding', () async {
    final md = await _run({
      _contentTypes: '<x/>',
      'xl/workbook.xml': '<?xml version="1.0"?>'
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="S" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels': '<?xml version="1.0"?>'
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Target="worksheets/sheet1.xml"/></Relationships>',
      'xl/worksheets/sheet1.xml': '<?xml version="1.0"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>H1</t></is></c>'
          '<c r="C1" t="inlineStr"><is><t>H3</t></is></c></row>'
          '<row r="2"><c r="B2" t="inlineStr"><is><t>only-B</t></is></c></row>'
          '</sheetData></worksheet>',
    });
    expect(md, contains('| H1 |  | H3 |'));
    expect(md, contains('|  | only-B |  |'));
  });

  test('workbook without rels → fallback Sheet N', () async {
    final md = await _run({
      _contentTypes: '<x/>',
      'xl/workbook.xml': '<workbook/>',
      'xl/worksheets/sheet1.xml': '<?xml version="1.0"?>'
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<sheetData><row r="1"><c r="A1" t="inlineStr"><is><t>X</t></is></c></row>'
          '</sheetData></worksheet>',
    });
    expect(md, contains('# Sheet 1'));
    expect(md, contains('| X |'));
  });

  test('no worksheet entries → corrupt', () async {
    expect(
      () => const XlsxExtractor().extract(
        bytes: buildZip({_contentTypes: '<x/>'}),
        output: MemoryOutput(),
      ),
      throwsA(isA<ConvertException>()),
    );
  });
}
