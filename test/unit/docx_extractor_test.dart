import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/docx_extractor.dart';
import 'package:markit/core/markdown_writer.dart';
import 'package:markit/core/output.dart';

import '../helpers/docx_factory.dart';

/// Jalankan extractor → string markdown (MemoryMdSink).
Future<String> _extract(Uint8List bytes, {String? path}) async {
  final buffer = StringBuffer();
  final sink = MemoryMdSink(buffer);
  final writer = MarkdownWriter(sink);
  final result = await const DocxExtractor().extract(
    bytes: path == null ? bytes : null,
    path: path,
    writer: writer,
  );
  await writer.close();
  expect(result.itemCount, greaterThan(0));
  return buffer.toString();
}

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
          writer: MarkdownWriter(MemoryMdSink(StringBuffer())),
        ),
        throwsA(isA<ConvertException>()
            .having((e) => e.type, 'type', ConvertError.corrupt)),
      );
    });

    test('zip tanpa word/document.xml → corrupt', () async {
      final bytes = buildTestDocx(documentXml: '');
      await expectLater(
        () => const DocxExtractor().extract(
          bytes: bytes,
          writer: MarkdownWriter(MemoryMdSink(StringBuffer())),
        ),
        throwsA(isA<ConvertException>()
            .having((e) => e.type, 'type', ConvertError.corrupt)),
      );
    });

    test('tanpa teks sama sekali → noText', () async {
      final bytes = buildTestDocx(
        documentXml: docxDocument('<w:sectPr/>'),
      );
      await expectLater(
        () => const DocxExtractor().extract(
          bytes: bytes,
          writer: MarkdownWriter(MemoryMdSink(StringBuffer())),
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
}
