import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/inline_executor.dart';

import '../helpers/pdf_factory.dart';

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

    test('markdown passthrough via executor', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'j5',
        pdfPath: '',
        pdfBytes: Uint8List.fromList(utf8.encode('# Title\n\nBody.')),
        outputPath: 'notes.md',
        format: InputFormat.markdown,
      );

      expect(result.success, isTrue);
      expect(result.content, contains('# Title'));
      expect(result.content, contains('Body.'));

      await executor.shutdown();
    });

    test('format tanpa extractor (docx) → unsupported failure', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'j6',
        pdfPath: '',
        pdfBytes: Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]),
        outputPath: 'doc.md',
        format: InputFormat.docx,
      );

      expect(result.success, isFalse);
      expect(result.errorType, 'unsupported');

      await executor.shutdown();
    });

    test('json corrupt → corrupt failure, batch tetap lanjut', () async {
      final executor = InlineExecutor();
      await executor.initialize();

      final result = await executor.runJob(
        jobId: 'j7',
        pdfPath: '',
        pdfBytes: Uint8List.fromList(utf8.encode('{invalid')),
        outputPath: 'bad.md',
        format: InputFormat.json,
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
      expect(result.errorMessage, contains('Choose files'));

      await executor.shutdown();
    });
  });
}
