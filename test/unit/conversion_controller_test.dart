import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/isolate/conversion_executor.dart';
import 'package:markit/models/pdf_input.dart';

/// Fake executor: menulis file .md sungguhan ke [outputPath] (simulasi
/// hasil konversi) lalu sukses.
class _WritingExecutor implements ConversionExecutor {
  @override
  Future<void> initialize() async {}

  @override
  Future<JobExecutionResult> runJob({
    required String jobId,
    required String pdfPath,
    Uint8List? pdfBytes,
    required String outputPath,
    InputFormat format = InputFormat.pdf,
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  }) async {
    File(outputPath).writeAsStringSync('# hasil $jobId');
    return JobExecutionResult(
      success: true,
      pageCount: 1,
      failedPages: const [],
      bodyFontSize: 12,
      outputPath: outputPath,
      content: '# hasil $jobId',
    );
  }

  @override
  void cancel() {}

  @override
  void resetCancel() {}

  @override
  Future<void> shutdown() async {}
}

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
      expect(a.errorMessage, contains('Unexpected error'));
      expect(b.status, JobStatus.done); // batch lanjut
      expect(controller.isRunning, isFalse);
    });
  });

  group('format legacy (graceful unsupported)', () {
    test('.doc → failed dengan errorType unsupported, batch tetap lanjut',
        () async {
      final controller = BatchConversionController(executor: _WritingExecutor());
      controller.addFiles([
        PdfInput(name: 'a.doc', path: 'C:/a.doc', format: InputFormat.word),
        PdfInput(name: 'b.pdf', path: 'C:/b.pdf'),
      ]);
      final a = controller.queue[0];
      final b = controller.queue[1];

      await controller.convertAll();

      expect(a.status, JobStatus.failed);
      expect(a.errorType, 'unsupported');
      expect(a.errorMessage, contains('Word (.doc)'));
      expect(b.status, JobStatus.done); // batch lanjut ke file berikutnya
      expect(controller.isRunning, isFalse);
    });

    test('.xlsx modern → diproses executor (bukan legacy check)', () async {
      final controller = BatchConversionController(executor: _WritingExecutor());
      controller.addFiles([
        PdfInput(
          name: 'a.xlsx',
          path: 'C:/a.xlsx',
          format: InputFormat.excel,
        ),
      ]);

      await controller.convertAll();

      expect(controller.queue.single.status, JobStatus.done);
    });
  });

  group('output temp batch (tidak auto-simpan ke folder sumber)', () {
    test('desktop: hasil konversi ditulis ke temp, bukan folder sumber',
        () async {
      final controller = BatchConversionController(executor: _WritingExecutor());
      controller.addFiles([
        PdfInput(name: 'a.pdf', path: 'C:/docs/a.pdf'),
      ]);
      final job = controller.queue.single;
      final sourceOutput = job.outputPath; // default: folder sumber
      expect(sourceOutput, 'C:/docs/a.md');

      await controller.convertAll();

      expect(job.status, JobStatus.done);
      // OutputPath di-override ke direktori temp batch.
      expect(job.outputPath, isNot(sourceOutput));
      expect(job.outputPath, contains('markit_batch'));
      expect(job.outputPath, endsWith('a.md'));
      // Hasil ada di temp, folder sumber TIDAK tersentuh.
      expect(File(job.outputPath).existsSync(), isTrue);
      expect(File('C:/docs/a.md').existsSync(), isFalse);

      // Cleanup setelah alur Save → file temp dibuang.
      await controller.cleanupTempOutputs();
      expect(File(job.outputPath).existsSync(), isFalse);
    });

    test('reset membersihkan output temp batch', () async {
      final controller = BatchConversionController(executor: _WritingExecutor());
      controller.addFiles([PdfInput(name: 'a.pdf', path: 'C:/docs/a.pdf')]);
      await controller.convertAll();
      final tempPath = controller.queue.single.outputPath;
      expect(File(tempPath).existsSync(), isTrue);

      controller.reset();
      expect(File(tempPath).existsSync(), isFalse);
    });

    test('web (tanpa path): outputPath tetap nama file, bukan temp', () async {
      final controller = BatchConversionController(executor: _WritingExecutor());
      controller.addFiles([
        PdfInput(name: 'a.pdf', sizeBytes: 1, bytes: Uint8List(0)),
      ]);
      await controller.convertAll();
      final job = controller.queue.single;
      expect(job.outputPath, 'a.md'); // web: tanpa filesystem
      expect(job.outputPath, isNot(contains('markit_batch')));
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

  group('convertAll — robustness (web / temp-dir failures)', () {
    test('temp dir null (web, no filesystem) → job still processed, '
        'outputPath = file name', () async {
      final controller = _TempDirController(
        executor: _WritingExecutor(),
        tempDirResult: null,
      );
      controller.addFiles([
        PdfInput(name: 'a.pdf', sizeBytes: 1, bytes: Uint8List(0)),
      ]);
      final job = controller.queue.single;

      await controller.convertAll();

      // Web wedge regression: convertAll used to call
      // Directory.systemTemp.createTemp without a kIsWeb guard — on web,
      // dart:io throws UnsupportedError before any job runs, _isRunning was
      // never reset, and the UI got stuck on "Processing" forever.
      expect(job.status, JobStatus.done);
      expect(job.outputPath, 'a.md');
      expect(job.outputPath, isNot(contains('markit_batch')));
      expect(controller.isRunning, isFalse);
    });

    test('temp dir throw → batch fails but controller is not wedged '
        '(isRunning reset, job not stuck running)', () async {
      final controller = _TempDirController(
        executor: _WritingExecutor(),
        tempDirError: StateError('fs unavailable'),
      );
      controller.addFiles([
        PdfInput(name: 'a.pdf', path: 'C:/docs/a.pdf'),
      ]);
      final job = controller.queue.single;

      await expectLater(controller.convertAll(), throwsStateError);

      expect(controller.isRunning, isFalse);
      expect(job.status, JobStatus.queued); // not stuck running forever
    });
  });
}

/// Subclass with a controllable [BatchConversionController.ensureTempOutputDir]
/// seam — simulates the web build (null) or filesystem failures (throw).
class _TempDirController extends BatchConversionController {
  _TempDirController({
    required super.executor,
    this.tempDirResult,
    this.tempDirError,
  });

  final Directory? tempDirResult;
  final Object? tempDirError;

  @override
  Future<Directory?> ensureTempOutputDir() {
    if (tempDirError != null) {
      throw tempDirError!;
    }
    return Future.value(tempDirResult);
  }
}
