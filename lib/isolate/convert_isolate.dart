import 'dart:isolate';

import '../core/errors.dart';
import '../core/extractors/extractor_registry.dart';
import '../core/input_format.dart';
import '../core/output.dart';
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

/// Runs one job through the extractor registry — PDF and semantic formats
/// share ONE code path (the format-specific behavior lives behind the seam).
Future<void> _runJob(
  SendPort mainPort,
  StartConvert start,
  bool Function() isCancelled,
) async {
  final format = InputFormat.values.firstWhere(
    (f) => f.name == start.formatName,
    orElse: () => InputFormat.pdf,
  );

  final extractor = ExtractorRegistry.forFormat(format);
  if (extractor == null) {
    mainPort.send(ConvertFailed(
      jobId: start.jobId,
      errorType: 'unsupported',
      message: 'Format ${format.label} is not yet supported for conversion.',
    ));
    return;
  }

  try {
    final result = await extractor.extract(
      bytes: null,
      path: start.pdfPath,
      output: FileOutput(start.outputPath),
      onProgress: (done, total, phase, elapsedMs) {
        mainPort.send(ConvertProgress(
          jobId: start.jobId,
          page: done,
          total: total,
          elapsedMs: elapsedMs,
          phase: phase,
        ));
      },
      isCancelled: isCancelled,
    );
    mainPort.send(ConvertDone(
      jobId: start.jobId,
      outputPath: result.outputPath ?? start.outputPath,
      pageCount: result.itemCount,
      failedPages: result.failedPages,
      elapsedMs: result.elapsed.inMilliseconds,
      bodyFontSize: result.bodyFontSize,
      emptyPages: result.emptyPages,
    ));
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
