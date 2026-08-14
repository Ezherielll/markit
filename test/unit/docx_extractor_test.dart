import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/docx_extractor.dart';
import 'package:markit/core/output.dart';

import '../helpers/docx_factory.dart';

/// Run the extractor → markdown string (MemoryOutput).
Future<String> _extract(Uint8List bytes, {String? path}) async {
  final output = MemoryOutput();
  final result = await const DocxExtractor().extract(
    bytes: path == null ? bytes : null,
    path: path,
    output: output,
  );
  expect(result.itemCount, greaterThan(0));
  return output.content;
}

/// Sel tabel `<w:tc>` berisi satu paragraf polos (tanpa styleId/numId).
String _tc(String runs) => '<w:tc>${docxParagraph(runs)}</w:tc>';

void main() {
  group('DocxExtractor — parsing inti', () {
    test('paragraf + heading via styles.xml → markdown', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph(docxRun('Judul Besar'), styleId: 'Heading1') +
              docxParagraph(docxRun('Ini paragraf biasa.')),
        ),
        stylesXml: docxStyles([
          ('Heading1', 'Heading 1'),
        ]),
      );
      final md = await _extract(bytes);
      expect(md, contains('# Judul Besar'));
      expect(md, contains('Ini paragraf biasa.'));
    });

    test('heading level 1-3 terdeteksi dari nama style', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph(docxRun('H1'), styleId: 's1') +
              docxParagraph(docxRun('H2'), styleId: 's2') +
              docxParagraph(docxRun('H3'), styleId: 's3'),
        ),
        stylesXml: docxStyles([
          ('s1', 'heading 1'),
          ('s2', 'heading 2'),
          ('s3', 'heading 3'),
        ]),
      );
      final md = await _extract(bytes);
      expect(md, contains('# H1'));
      expect(md, contains('## H2'));
      expect(md, contains('### H3'));
    });

    test('numPr → list item (bullet)', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph(docxRun('Item satu'), numId: '1') +
              docxParagraph(docxRun('Item dua'), numId: '1'),
        ),
      );
      final md = await _extract(bytes);
      expect(md, contains('- Item satu'));
      expect(md, contains('- Item dua'));
    });

    test('multi-run satu paragraf → teks digabung', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph(docxRun('Hello ') + docxRun('world!')),
        ),
      );
      final md = await _extract(bytes);
      expect(md, contains('Hello world!'));
    });

    test('bukan zip → ConvertException corrupt', () async {
      await expectLater(
        () => const DocxExtractor().extract(
          bytes: Uint8List.fromList([1, 2, 3]),
          output: MemoryOutput(),
        ),
        throwsA(isA<ConvertException>()
            .having((e) => e.type, 'type', ConvertError.corrupt)),
      );
    });

    test('entry document.xml kosong → corrupt (XML tidak valid)', () async {
      final bytes = buildTestDocx(documentXml: '');
      await expectLater(
        () => const DocxExtractor().extract(
          bytes: bytes,
          output: MemoryOutput(),
        ),
        throwsA(isA<ConvertException>()
            .having((e) => e.type, 'type', ConvertError.corrupt)),
      );
    });

    test('zip tanpa word/document.xml → corrupt', () async {
      final bytes = buildTestDocx(
        documentXml: '',
        includeDocumentXml: false,
      );
      await expectLater(
        () => const DocxExtractor().extract(
          bytes: bytes,
          output: MemoryOutput(),
        ),
        throwsA(isA<ConvertException>()
            .having((e) => e.type, 'type', ConvertError.corrupt)
            .having(
              (e) => e.message,
              'message',
              contains('no word/document.xml'),
            )),
      );
    });

    test('tanpa teks sama sekali → noText', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument('<w:sectPr/>'),
      );
      await expectLater(
        () => const DocxExtractor().extract(
          bytes: bytes,
          output: MemoryOutput(),
        ),
        throwsA(isA<ConvertException>()
            .having((e) => e.type, 'type', ConvertError.noText)),
      );
    });

    test('desktop path (bytes null) → hasil sama', () async {
      final dir = await Directory.systemTemp.createTemp('markit_docx');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/a.docx');
      file.writeAsBytesSync(buildTestDocx(
        documentXml: docxDocument(docxParagraph(docxRun('Dari path'))),
      ));
      final md = await _extract(Uint8List(0), path: file.path);
      expect(md, contains('Dari path'));
    });
  });

  group('DocxExtractor — tabel & ordered list', () {
    test('w:tbl → tabel markdown + separator (sel w:tc)', () async {
      final tbl =
          '<w:tbl>'
          '<w:tr>${_tc(docxRun('Name'))}${_tc(docxRun('Qty'))}</w:tr>'
          '<w:tr>${_tc(docxRun('Apples'))}${_tc(docxRun('10'))}</w:tr>'
          '</w:tbl>';
      final bytes = buildTestDocx(documentXml: docxDocument(tbl));
      final md = await _extract(bytes);
      expect(md, contains('| Name | Qty |'));
      expect(md, contains('| --- | --- |'));
      expect(md, contains('| Apples | 10 |'));
    });

    test("sel w:tc berisi '|' → di-escape", () async {
      final tbl =
          '<w:tbl>'
          '<w:tr>${_tc(docxRun('a|b'))}${_tc(docxRun('c'))}</w:tr>'
          '</w:tbl>';
      final bytes = buildTestDocx(documentXml: docxDocument(tbl));
      final md = await _extract(bytes);
      expect(md, contains(r'| a\|b | c |'));
    });

    test('sel w:p langsung (tanpa w:tc, format ringkas) → tetap jadi sel', () async {
      final tbl =
          '<w:tbl>'
          '<w:tr>${docxParagraph(docxRun('A'))}'
          '${docxParagraph(docxRun('B'))}</w:tr>'
          '</w:tbl>';
      final bytes = buildTestDocx(documentXml: docxDocument(tbl));
      final md = await _extract(bytes);
      expect(md, contains('| A | B |'));
    });

    test('numFmt decimal → ordered list dengan listIndex increment', () async {
      final numberingXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:numbering xmlns:w="http://schemas.openxmlformats.org/'
          'wordprocessingml/2006/main">'
          '<w:abstractNum w:abstractNumId="0">'
          '<w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl>'
          '</w:abstractNum>'
          '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
          '</w:numbering>';
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph(docxRun('Pertama'), numId: '1') +
              docxParagraph(docxRun('Kedua'), numId: '1') +
              docxParagraph(docxRun('Bukan list')),
        ),
        numberingXml: numberingXml,
      );
      final md = await _extract(bytes);
      expect(md, contains('1. Pertama'));
      expect(md, contains('2. Kedua'));
      expect(md, contains('Bukan list'));
    });

    test('numFmt bullet → unordered list', () async {
      final numberingXml =
          '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
          '<w:numbering xmlns:w="http://schemas.openxmlformats.org/'
          'wordprocessingml/2006/main">'
          '<w:abstractNum w:abstractNumId="0">'
          '<w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl>'
          '</w:abstractNum>'
          '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
          '</w:numbering>';
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph(docxRun('Butir'), numId: '1'),
        ),
        numberingXml: numberingXml,
      );
      final md = await _extract(bytes);
      expect(md, contains('- Butir'));
    });

    test('w:tab dan w:br → spasi, bukan karakter aneh', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph('<w:r><w:tab/><w:t>teks</w:t>'
              '<w:br/><w:t>lanjut</w:t></w:r>'),
        ),
      );
      final md = await _extract(bytes);
      expect(md, isNot(contains('\t')));
      expect(md, contains('teks lanjut'));
    });

    test('progress dipanggil + cancel menghentikan ekstraksi', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument(
          docxParagraph(docxRun('satu')) +
              docxParagraph(docxRun('dua')) +
              docxParagraph(docxRun('tiga')),
        ),
      );
      var calls = 0;
      var cancelled = false;
      final output = MemoryOutput();
      final result = await const DocxExtractor().extract(
        bytes: bytes,
        output: output,
        onProgress: (done, total, phase, elapsedMs) => calls = done,
        isCancelled: () {
          cancelled = true;
          return true; // cancel sejak awal → berhenti setelah blok pertama
        },
      );
      expect(result.itemCount, lessThan(3));
      expect(calls, lessThan(3));
      expect(cancelled, isTrue);
    });
  });
}
