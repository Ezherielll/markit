import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/inline_executor.dart';

import '../helpers/pdf_factory.dart';
import '../helpers/zip_factory.dart';

// ---- Synthetic fixtures (copied from the per-parser tests; kept inline —
// ---- duplicating 5 small builders beats refactoring 5 parser test files).

const _epubContainer = '<?xml version="1.0"?>'
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

const _epubOpf = '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
    '<manifest><item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/></manifest>'
    '<spine><itemref idref="ch1"/><itemref idref="ch2"/></spine></package>';

String _odfContent(String body) => '<?xml version="1.0" encoding="UTF-8"?>'
    '<office:document-content xmlns:office="urn:oasis:names:tc:opendocument:xmlns:office:1.0" '
    'xmlns:text="urn:oasis:names:tc:opendocument:xmlns:text:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0">'
    '<office:body>$body</office:body></office:document-content>';

String _pptxSlide(String title, String body, {String? bullets, String? table}) =>
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Uint8List pdfBytes;

  setUp(() {
    pdfBytes = buildTestPdf();
  });

  test('inline: convert bytes → success + content (web path)', () async {
    final executor = InlineExecutor();
    await executor.initialize();

    final progress = <int>[];
    final result = await executor.runJob(
      jobId: 'j1',
      pdfPath: '',
      pdfBytes: pdfBytes,
      outputPath: 'book.md',
      onProgress: (page, total, phase, elapsedMs) => progress.add(page),
    );

    expect(result.success, isTrue);
    expect(result.pageCount, 3);
    expect(result.content, contains('# The Quick Brown Fox'));
    expect(result.content, contains('- Item one'));
    expect(result.outputPath, 'book.md');
    expect(progress, containsAll([0, 1, 2, 3]));

    await executor.shutdown();
  });

  test('inline: cancel → job gagal, tidak hang (FR-11)', () async {
    final executor = InlineExecutor();
    await executor.initialize();

    var cancelled = false;
    final result = await executor.runJob(
      jobId: 'j2',
      pdfPath: '',
      pdfBytes: pdfBytes,
      outputPath: 'book.md',
      onProgress: (page, total, phase, elapsedMs) {
        if (page >= 1 && !cancelled) {
          cancelled = true;
          executor.cancel();
        }
      },
    );

    // Converter melempar _CancelledException → InlineExecutor menangkapnya
    // sebagai failure (bukan hang).
    expect(result.success, isFalse);
    expect(result.errorType, isNotNull);

    await executor.shutdown();
  });

  test('inline: corrupt bytes → failure (FR-10a)', () async {
    final executor = InlineExecutor();
    await executor.initialize();

    final result = await executor.runJob(
      jobId: 'j3',
      pdfPath: '',
      pdfBytes: Uint8List.fromList(List.filled(1024, 0x42)),
      outputPath: 'bad.md',
    );

    expect(result.success, isFalse);
    expect(result.errorType, isNotNull);

    await executor.shutdown();
  });

  group('inline: semantic extractor (non-PDF, web path)', () {
    test('csv bytes → tabel markdown via executor', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'j4',
        pdfPath: '',
        pdfBytes: Uint8List.fromList(utf8.encode('A,B\n1,2')),
        outputPath: 'data.md',
        format: InputFormat.csv,
      );

      expect(result.success, isTrue);
      expect(result.content, contains('| A | B |'));
      expect(result.content, contains('| 1 | 2 |'));
      expect(result.pageCount, 2);

      await executor.shutdown();
    });

    test('word corrupt (bukan ZIP) → corrupt failure, batch tetap lanjut',
        () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'j5',
        pdfPath: '',
        pdfBytes: Uint8List.fromList([0x01, 0x02, 0x03]),
        outputPath: 'bad.md',
        format: InputFormat.word,
      );

      expect(result.success, isFalse);
      expect(result.errorType, 'corrupt');

      await executor.shutdown();
    });

    test('epub corrupt (not ZIP) → corrupt failure, batch continues',
        () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'j6',
        pdfPath: '',
        pdfBytes: Uint8List.fromList(utf8.encode('ZIP')),
        outputPath: 'book.md',
        format: InputFormat.epub,
      );

      expect(result.success, isFalse);
      expect(result.errorType, 'corrupt');

      await executor.shutdown();
    });

    test('semantic tanpa bytes (drop path palsu) → unsupported, bukan corrupt',
        () async {
      final executor = InlineExecutor();
      await executor.initialize();

      // Bugfix: web tidak punya filesystem — extractor tidak boleh dipanggil
      // dengan path placeholder (sebelumnya UnsupportedError → corrupt).
      final result = await executor.runJob(
        jobId: 'j8',
        pdfPath: 'C:/fakepath/data.csv',
        pdfBytes: null,
        outputPath: 'data.md',
        format: InputFormat.csv,
      );

      expect(result.success, isFalse);
      expect(result.errorType, 'unsupported');
      expect(result.errorMessage, contains('Choose Files'));

      await executor.shutdown();
    });

    test('inline: pdf without bytes → unsupported (web null-bytes guard)',
        () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'j-null-pdf',
        pdfPath: 'C:/fakepath/book.pdf',
        pdfBytes: null,
        outputPath: 'book.md',
        format: InputFormat.pdf,
      );

      expect(result.success, isFalse);
      expect(result.errorType, 'unsupported');
      expect(result.errorMessage, contains('Choose Files'));

      await executor.shutdown();
    });
  });

  group('inline: end-to-end per family (web path)', () {
    test('powerpoint pptx bytes → slide markdown via executor', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'e2e-pptx',
        pdfPath: '',
        pdfBytes: buildZip({
          'ppt/slides/slide1.xml': _pptxSlide(
            'Intro',
            'Welcome to the deck.',
            bullets: '<a:p><a:pPr><a:buChar char="&#8226;"/></a:pPr>'
                '<a:r><a:t>Point one</a:t></a:r></a:p>',
          ),
          'ppt/slides/slide2.xml': _pptxSlide('Closing', 'Thanks.'),
        }),
        outputPath: 'deck.md',
        format: InputFormat.powerpoint,
      );

      expect(result.success, isTrue);
      expect(result.content, contains('# Intro'));
      expect(result.content, contains('Welcome to the deck.'));
      expect(result.content, contains('- Point one'));
      expect(result.content, contains('# Closing'));

      await executor.shutdown();
    });

    test('excel xlsx bytes → workbook markdown via executor', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'e2e-xlsx',
        pdfPath: '',
        pdfBytes: buildZip({
          '[Content_Types].xml': '<x/>',
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
        }),
        outputPath: 'data.md',
        format: InputFormat.excel,
      );

      expect(result.success, isTrue);
      expect(result.content, contains('# Data'));
      expect(result.content, contains('| Name | Age |'));
      expect(result.content, contains('| Alice | 30 |'));

      await executor.shutdown();
    });

    test('opendocument odt bytes → document markdown via executor', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'e2e-odf',
        pdfPath: '',
        pdfBytes: buildZip({
          'content.xml': _odfContent(
            '<office:text>'
            '<text:h text:outline-level="1">Chapter One</text:h>'
            '<text:p>First paragraph.</text:p>'
            '<text:list><text:list-item><text:p>Alpha</text:p></text:list-item>'
            '<text:list-item><text:p>Beta</text:p></text:list-item></text:list>'
            '</office:text>',
          ),
        }),
        outputPath: 'doc.md',
        format: InputFormat.opendocument,
      );

      expect(result.success, isTrue);
      expect(result.content, contains('# Chapter One'));
      expect(result.content, contains('First paragraph.'));
      expect(result.content, contains('- Alpha'));
      expect(result.content, contains('- Beta'));

      await executor.shutdown();
    });

    test('rtf bytes → text markdown via executor', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'e2e-rtf',
        pdfPath: '',
        pdfBytes:
            Uint8List.fromList(utf8.encode(r'{\rtf1\ansi Hello {\b bold} and {\i italic}.\par Second paragraph.}')),
        outputPath: 'text.md',
        format: InputFormat.rtf,
      );

      expect(result.success, isTrue);
      expect(result.content, contains('Hello **bold** and *italic*.'));
      expect(result.content, contains('Second paragraph.'));

      await executor.shutdown();
    });

    test('epub bytes → spine chapters markdown via executor', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'e2e-epub',
        pdfPath: '',
        pdfBytes: buildZip({
          'META-INF/container.xml': _epubContainer,
          'OEBPS/content.opf': _epubOpf,
          'OEBPS/ch1.xhtml': '<html><body><h1>Chapter One</h1>'
              '<p>First <strong>bold</strong> paragraph.</p>'
              '<ul><li>One</li><li>Two</li></ul></body></html>',
          'OEBPS/ch2.xhtml': '<html><body><h2>Section Two</h2>'
              '<p>See <a href="https://example.com">docs</a>.</p></body></html>',
        }),
        outputPath: 'book.md',
        format: InputFormat.epub,
      );

      expect(result.success, isTrue);
      expect(result.content, contains('# Chapter One'));
      expect(result.content, contains('First **bold** paragraph.'));
      expect(result.content, contains('- One'));
      expect(result.content, contains('## Section Two'));
      expect(result.content, contains('docs (https://example.com)'));

      await executor.shutdown();
    });
  });
}
