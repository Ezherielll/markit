import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/isolate/inline_executor.dart';

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
}
