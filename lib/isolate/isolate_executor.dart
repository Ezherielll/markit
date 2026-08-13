import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import '../core/input_format.dart';
import 'conversion_executor.dart';
import 'convert_isolate.dart';
import 'messages.dart';

/// Execution via PERSISTENT worker isolate (desktop).
///
/// pdfrx/PDFium is not safe to repeatedly spawn/teardown in a single process
/// ("Cannot invoke native callback from a different isolate") — one worker
/// is used for the entire lifetime of the app; subsequent batches reuse + ResetCancel.
class IsolateExecutor implements ConversionExecutor {
  IsolatePorts? _ports;

  /// Active jobs (jobId → completer+progress). Concurrent routing: single
  /// persistent handler distributes worker messages per jobId.
  final Map<String, _PendingJob> _pending = {};

  @override
  Future<void> initialize() async {
    _ports ??= await _spawnWorker();
  }

  @override
  Future<JobExecutionResult> runJob({
    required String jobId,
    required String pdfPath,
    Uint8List? pdfBytes,
    required String outputPath,
    InputFormat format = InputFormat.pdf,
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  }) async {
    final ports = _ports!;
    final completer = Completer<JobExecutionResult>();
    _pending[jobId] = _PendingJob(completer, onProgress);

    ports.commandPort!.send(StartConvert(
      jobId: jobId,
      pdfPath: pdfPath,
      outputPath: outputPath,
      formatName: format.name,
    ));

    return completer.future.timeout(
      const Duration(minutes: 30),
      onTimeout: () {
        _pending.remove(jobId);
        return JobExecutionResult.failure(
          'corrupt',
          'Conversion exceeded 30-minute timeout.',
        );
      },
    );
  }

  @override
  void cancel() {
    _ports?.cancelSender?.send(const CancelRequest());
  }

  @override
  void resetCancel() {
    _ports?.commandPort?.send(const ResetCancel());
  }

  @override
  Future<void> shutdown() async {
    final ports = _ports;
    _ports = null;
    if (ports != null) {
      ports.commandPort?.send(const Shutdown());
      await ports.dispose();
    }
  }

  /// Spawn a single persistent worker + wire ports.
  Future<IsolatePorts> _spawnWorker() async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      convertIsolateMain,
      receivePort.sendPort,
    );

    final exitPort = ReceivePort();
    isolate.addOnExitListener(exitPort.sendPort);

    final ports = IsolatePorts(
      isolate: isolate,
      receivePort: receivePort,
      exitPort: exitPort,
    );

    // Persistent handler (active immediately): capture command/cancel ports
    // sent by worker on spawn, then route job messages per jobId.
    ports.subscription = receivePort.listen((message) {
      if (message is SendPort && ports.commandPort == null) {
        ports.commandPort = message;
        return;
      }
      if (message is SendPort && ports.cancelSender == null) {
        ports.cancelSender = message;
        return;
      }
      _routeMessage(message);
    });

    // Ensure worker ports are registered before first job is sent.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((ports.commandPort == null || ports.cancelSender == null) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return ports;
  }

  /// Route worker messages to corresponding job (via jobId).
  void _routeMessage(dynamic message) {
    if (message is ConvertProgress) {
      final job = _pending[message.jobId];
      job?.onProgress?.call(
        message.page,
        message.total,
        message.phase,
        message.elapsedMs,
      );
      return;
    }
    if (message is ConvertDone) {
      final job = _pending.remove(message.jobId);
      if (job != null && !job.completer.isCompleted) {
        job.completer.complete(JobExecutionResult(
          success: true,
          pageCount: message.pageCount,
          failedPages: message.failedPages,
          bodyFontSize: message.bodyFontSize,
          outputPath: message.outputPath,
        ));
      }
      return;
    }
    if (message is ConvertFailed) {
      final job = _pending.remove(message.jobId);
      if (job != null && !job.completer.isCompleted) {
        job.completer.complete(JobExecutionResult.failure(
          message.errorType,
          message.message,
        ));
      }
    }
  }
}

/// Active job in executor — completer + progress callback (jobId routing).
class _PendingJob {
  _PendingJob(this.completer, this.onProgress);

  final Completer<JobExecutionResult> completer;
  final void Function(int page, int total, int phase, int elapsedMs)? onProgress;
}

class IsolatePorts {
  IsolatePorts({
    required this.isolate,
    required this.receivePort,
    required this.exitPort,
  });

  final Isolate isolate;
  final ReceivePort receivePort;
  late StreamSubscription<dynamic> subscription;
  final ReceivePort exitPort;

  /// Worker command port (received during spawn).
  SendPort? commandPort;

  /// Worker cancel port (received during spawn).
  SendPort? cancelSender;

  Future<void> dispose() async {
    await subscription.cancel();
    receivePort.close();
    // Wait for worker exit (after Shutdown) — worker closes command
    // port & PDFium; MUST NOT be forcibly killed (native PDFium callback crash).
    await exitPort.first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    exitPort.close();
  }
}
