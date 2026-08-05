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

    ports.setHandler!((message) {
      if (message is ConvertProgress) {
        onProgress?.call(
          message.page,
          message.total,
          message.phase,
          message.elapsedMs,
        );
      } else if (message is ConvertDone) {
        if (!completer.isCompleted) {
          completer.complete(JobExecutionResult(
            success: true,
            pageCount: message.pageCount,
            failedPages: message.failedPages,
            bodyFontSize: message.bodyFontSize,
            outputPath: message.outputPath,
          ));
        }
      } else if (message is ConvertFailed) {
        if (!completer.isCompleted) {
          completer.complete(JobExecutionResult.failure(
            message.errorType,
            message.message,
          ));
        }
      }
    });

    ports.commandPort!.send(StartConvert(
      jobId: jobId,
      pdfPath: pdfPath,
      outputPath: outputPath,
    ));

    return completer.future.timeout(
      const Duration(minutes: 30),
      onTimeout: () => JobExecutionResult.failure(
        'corrupt',
        'Konversi melebihi batas waktu 30 menit.',
      ),
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

    // Handler default (langsung aktif): tangkap command/cancel port yang
    // dikirim worker saat spawn — jangan sampai terlewat sebelum job pertama.
    void Function(dynamic message)? jobHandler;
    ports.subscription = receivePort.listen((message) {
      if (message is SendPort && ports.commandPort == null) {
        ports.commandPort = message;
        return;
      }
      if (message is SendPort && ports.cancelSender == null) {
        ports.cancelSender = message;
        return;
      }
      jobHandler?.call(message);
    });
    ports.setHandler = (h) => jobHandler = h;

    // Pastikan port worker sudah terdaftar sebelum job pertama dikirim.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((ports.commandPort == null || ports.cancelSender == null) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return ports;
  }
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

  /// Ganti handler pesan untuk job aktif (Progress/Done/Failed).
  void Function(void Function(dynamic) handler)? setHandler;

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
