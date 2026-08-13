import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/isolate/conversion_executor.dart';
import 'package:markit/models/pdf_input.dart';

/// Fake executor: throw untuk jobId tertentu, sukses untuk lainnya.
class _ThrowingExecutor implements ConversionExecutor {
  /// Id job yang sengaja dilempar. Diisi SETELAH addFiles — id job
  /// bergantung timestamp (`job-<micros>-<counter>`).
  String failJobId = '';
  bool initialized = false;

  @override
  Future<void> initialize() async => initialized = true;

  @override
  Future<JobExecutionResult> runJob({
    required String jobId,
    required String pdfPath,
    Uint8List? pdfBytes,
    required String outputPath,
    InputFormat format = InputFormat.pdf,
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  }) async {
    if (jobId == failJobId) {
      throw StateError('boom'); // bug internal — harusnya job failed, bukan batch crash
    }
    return JobExecutionResult(
      success: true,
      pageCount: 1,
      failedPages: const [],
      bodyFontSize: 12,
      outputPath: outputPath,
      content: '# ok',
    );
  }

  @override
  void cancel() {}

  @override
  void resetCancel() {}

  @override
  Future<void> shutdown() async {}
}

void main() {
  group('resilience batch (satu job throw)', () {
    test('satu job throw → job failed, batch tetap selesai, job lain done',
        () async {
      final executor = _ThrowingExecutor();
      final controller = BatchConversionController(executor: executor);
      controller.addFiles([
        PdfInput(name: 'a.pdf', path: 'C:/a.pdf'),
        PdfInput(name: 'b.pdf', path: 'C:/b.pdf'),
      ]);
      final a = controller.queue[0];
      final b = controller.queue[1];
      executor.failJobId = a.id; // job 'bad' = a (pertama di queue)

      await controller.convertAll();

      expect(a.status, JobStatus.failed); // throw → failed, bukan crash
      expect(a.errorType, 'corrupt');
      expect(a.errorMessage, contains('Kesalahan tak terduga'));
      expect(b.status, JobStatus.done); // batch lanjut
      expect(controller.isRunning, isFalse);
    });
  });

  group('QueuedFile.outputPath (fase pilih lokasi)', () {
    test('desktop: path sumber → ekstensi .md', () {
      final job = QueuedFile(
        id: '1',
        input: PdfInput(name: 'a.pdf', path: 'C:/docs/a.pdf'),
      );
      expect(job.outputPath, 'C:/docs/a.md');
    });

    test('web (tanpa path): nama → .md', () {
      final job = QueuedFile(
        id: '1',
        input: PdfInput(
          name: 'a.pdf',
          sizeBytes: 1,
          bytes: Uint8List(0),
        ),
      );
      expect(job.outputPath, 'a.md');
    });

    test('setter outputPath (setelah file dipindah ke folder pilihan)', () {
      final job = QueuedFile(
        id: '1',
        input: PdfInput(name: 'a.pdf', path: 'C:/docs/a.pdf'),
      );
      job.outputPath = 'D:/out/a.md';
      expect(job.outputPath, 'D:/out/a.md');
    });
  });
}
