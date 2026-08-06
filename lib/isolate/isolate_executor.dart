import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'conversion_executor.dart';
import 'convert_isolate.dart';
import 'messages.dart';

/// Eksekusi via worker isolate PERSIST (desktop).
///
/// pdfrx/PDFium tidak aman di-spawn/teardown berulang dalam satu proses
/// ("Cannot invoke native callback from a different isolate") — satu worker
/// dipakai untuk seluruh umur aplikasi; batch berikutnya reuse + ResetCancel.
class IsolateExecutor implements ConversionExecutor {
  IsolatePorts? _ports;

  /// Job aktif (jobId → completer+progress). Routing concurrent: satu
  /// handler persist mendistribusikan pesan worker per jobId (M2).
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
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  }) async {
    final ports = _ports!;
    final completer = Completer<JobExecutionResult>();
    _pending[jobId] = _PendingJob(completer, onProgress);

    ports.commandPort!.send(StartConvert(
      jobId: jobId,
      pdfPath: pdfPath,
      outputPath: outputPath,
    ));

    return completer.future.timeout(
      const Duration(minutes: 30),
      onTimeout: () {
        _pending.remove(jobId);
        return JobExecutionResult.failure(
          'corrupt',
          'Konversi melebihi batas waktu 30 menit.',
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

  /// Spawn satu worker persist + wire ports.
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

    // Handler persist (langsung aktif): tangkap command/cancel port yang
    // dikirim worker saat spawn, lalu routing pesan job per jobId (M2).
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

    // Pastikan port worker sudah terdaftar sebelum job pertama dikirim.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((ports.commandPort == null || ports.cancelSender == null) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return ports;
  }

  /// Distribusikan pesan worker ke job yang sesuai (via jobId).
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

/// Job aktif di executor — completer + callback progress (routing jobId).
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

  /// Command port worker (diterima saat spawn).
  SendPort? commandPort;

  /// Cancel port worker (diterima saat spawn).
  SendPort? cancelSender;

  Future<void> dispose() async {
    await subscription.cancel();
    receivePort.close();
    // Tunggu worker exit (setelah Shutdown) — worker yang menutup command
    // port & PDFium; TIDAK boleh di-kill paksa (native callback PDFium crash).
    await exitPort.first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    exitPort.close();
  }
}
