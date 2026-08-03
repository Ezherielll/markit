import 'dart:isolate';

import '../core/converter.dart';
import '../core/errors.dart';
import '../core/pdfrx_source.dart';
import 'messages.dart';

/// Entry point worker isolate.
///
/// Protokol:
/// 1. main spawn isolate, kirim `SendPort` worker sebagai argumen spawn.
/// 2. worker balas dengan SendPort command-nya.
/// 3. main kirim [StartConvert] + satu `SendPort` cancel ke command port.
/// 4. worker kirim [ConvertProgress] / [ConvertDone] / [ConvertFailed] ke
///    sendPort main; batal lewat pesan [CancelRequest] pada cancel port.
void convertIsolateMain(SendPort mainPort) {
  final commandPort = ReceivePort();
  mainPort.send(commandPort.sendPort);

  commandPort.listen((message) async {
    if (message is StartConvert) {
      await _run(mainPort, commandPort, message);
    }
  });
}

Future<void> _run(
  SendPort mainPort,
  ReceivePort commandPort,
  StartConvert start,
) async {
  final cancelPort = ReceivePort();
  mainPort.send(cancelPort.sendPort);

  var cancelled = false;
  cancelPort.listen((msg) {
    if (msg is CancelRequest) cancelled = true;
  });

  try {
    final source = await PdfrxSource.open(start.pdfPath);
    // Phase 1 (reading): histogram — page 0 sebagai penanda.
    mainPort.send(ConvertProgress(
      page: 0,
      total: source.pageCount,
      elapsedMs: 0,
      phase: 0,
    ));
    final result = await Converter().convert(
      source: source,
      outputPath: start.outputPath,
      onProgress: (p) {
        mainPort.send(ConvertProgress(
          page: p.page,
          total: p.total,
          elapsedMs: p.elapsed.inMilliseconds,
          phase: 1,
        ));
      },
      isCancelled: () => cancelled,
    );
    mainPort.send(ConvertDone(
      outputPath: result.outputPath,
      pageCount: result.pageCount,
      failedPages: result.failedPages.map((p) => p + 1).toList(),
      elapsedMs: result.elapsed.inMilliseconds,
      bodyFontSize: result.stats.bodyFontSize,
      emptyPages: result.stats.emptyPages,
    ));
  } on ConvertException catch (e) {
    mainPort.send(ConvertFailed(
      errorType: e.type.name,
      message: e.message,
    ));
  } catch (e) {
    mainPort.send(ConvertFailed(
      errorType: ConvertError.corrupt.name,
      message: 'Kesalahan tak terduga: $e',
    ));
  } finally {
    cancelPort.close();
    commandPort.close();
  }
}
