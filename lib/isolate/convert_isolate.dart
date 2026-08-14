import 'dart:isolate';

import '../core/converter.dart';
import '../core/errors.dart';
import '../core/extractors/extractor_registry.dart';
import '../core/input_format.dart';
import '../core/output.dart';
import '../core/pdfrx_source.dart';
import 'messages.dart';

/// Entry point for persistent worker isolate (serves multiple jobs in a batch).
///
/// Protocol:
/// 1. main spawns isolate, sends worker `SendPort` as spawn argument.
/// 2. worker replies with its command SendPort.
/// 3. main sends [StartConvert] per file; worker replies with cancel SendPort
///    (once, before first job) then [ConvertProgress]/[ConvertDone]/
///    [ConvertFailed] per job.
/// 4. cancellation via [CancelRequest] on cancel port; completion via [Shutdown].
///
/// A single worker is reused for ALL jobs — pdfrx creates an internal
/// PdfrxEngineWorker per isolate; repeatedly spawning/teardown causes
/// crashes ("Cannot invoke native callback from a different isolate").
void convertIsolateMain(SendPort mainPort) {
  final commandPort = ReceivePort();
  mainPort.send(commandPort.sendPort);

  var cancelled = false;

  final cancelPort = ReceivePort();
  cancelPort.listen((msg) {
    if (msg is CancelRequest) cancelled = true;
  });
  mainPort.send(cancelPort.sendPort);

  commandPort.listen((message) async {
    if (message is StartConvert) {
      await _runJob(mainPort, message, () => cancelled);
    } else if (message is ResetCancel) {
      cancelled = false;
    } else if (message is Shutdown) {
      cancelPort.close();
      commandPort.close();
    }
  });
}

Future<void> _runJob(
  SendPort mainPort,
  StartConvert start,
  bool Function() isCancelled,
) async {
  final format = InputFormat.values.firstWhere(
    (f) => f.name == start.formatName,
    orElse: () => InputFormat.pdf,
  );

  if (format != InputFormat.pdf) {
    await _runSemantic(mainPort, start, isCancelled, format);
  } else {
    await _runPdf(mainPort, start, isCancelled);
  }
}

/// PDF path: existing heuristic pipeline (PdfrxSource → grouper → classifier),
/// streaming via path (memory efficient).
Future<void> _runPdf(
  SendPort mainPort,
  StartConvert start,
  bool Function() isCancelled,
) async {
  var cancelled = false;
  try {
    final source = await PdfrxSource.open(start.pdfPath);
    try {
      // Phase 1 (reading): histogram — page 0 marker.
      mainPort.send(ConvertProgress(
        jobId: start.jobId,
        page: 0,
        total: source.pageCount,
        elapsedMs: 0,
        phase: 0,
      ));
      final result = await Converter().convert(
        source: source,
        output: FileOutput(start.outputPath),
        onProgress: (p) {
          mainPort.send(ConvertProgress(
            jobId: start.jobId,
            page: p.page,
            total: p.total,
            elapsedMs: p.elapsed.inMilliseconds,
            phase: 1,
          ));
        },
        isCancelled: () => isCancelled() || cancelled,
      );
      mainPort.send(ConvertDone(
        jobId: start.jobId,
        outputPath: result.outputPath ?? '',
        pageCount: result.pageCount,
        failedPages: result.failedPages.map((p) => p + 1).toList(),
        elapsedMs: result.elapsed.inMilliseconds,
        bodyFontSize: result.profile.bodyFontSize,
        emptyPages: result.profile.emptyPages,
      ));
    } finally {
      // REQUIRED: close document before next job — per-job native PDFium handle
      // must be freed.
      await source.dispose();
    }
  } on ConvertException catch (e) {
    mainPort.send(ConvertFailed(
      jobId: start.jobId,
      errorType: e.type.name,
      message: e.message,
    ));
  } catch (e) {
    mainPort.send(ConvertFailed(
      jobId: start.jobId,
      errorType: ConvertError.corrupt.name,
      message: 'Unexpected error: $e',
    ));
  }
}

/// Semantic path (non-PDF): pure Dart extractor → markdown streaming.
Future<void> _runSemantic(
  SendPort mainPort,
  StartConvert start,
  bool Function() isCancelled,
  InputFormat format,
) async {
  final extractor = ExtractorRegistry.forFormat(format);
  OutputTarget? output;
  try {
    if (extractor == null) {
      mainPort.send(ConvertFailed(
        jobId: start.jobId,
        errorType: 'unsupported',
        message: 'Format ${format.label} is not yet supported for conversion.',
      ));
      return;
    }

    output = FileOutput(start.outputPath);

    final result = await extractor.extract(
      bytes: null,
      path: start.pdfPath,
      output: output,
      onProgress: (done, total, phase, elapsedMs) {
        mainPort.send(ConvertProgress(
          jobId: start.jobId,
          page: done,
          total: total,
          elapsedMs: elapsedMs,
          phase: phase,
        ));
      },
      isCancelled: () => isCancelled(),
    );

    mainPort.send(ConvertDone(
      jobId: start.jobId,
      outputPath: start.outputPath,
      pageCount: result.itemCount,
      failedPages: const [],
      elapsedMs: 0,
      bodyFontSize: 0,
      emptyPages: 0,
    ));
  } on ConvertException catch (e) {
    await output?.abort();
    mainPort.send(ConvertFailed(
      jobId: start.jobId,
      errorType: e.type.name,
      message: e.message,
    ));
  } catch (e) {
    await output?.abort();
    mainPort.send(ConvertFailed(
      jobId: start.jobId,
      errorType: ConvertError.corrupt.name,
      message: 'Unexpected error: $e',
    ));
  }
}
