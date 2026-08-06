import 'dart:isolate';

import '../core/converter.dart';
import '../core/errors.dart';
import '../core/extractors/extractor_registry.dart';
import '../core/input_format.dart';
import '../core/markdown_writer.dart';
import '../core/output.dart';
import '../core/pdfrx_source.dart';
import 'messages.dart';

/// Entry point worker isolate (PERSISTEN — melayani banyak job dalam batch).
///
/// Protokol:
/// 1. main spawn isolate, kirim `SendPort` worker sebagai argumen spawn.
/// 2. worker balas dengan SendPort command-nya.
/// 3. main kirim [StartConvert] per file; worker balas dengan SendPort cancel
///    (sekali saja, sebelum job pertama) lalu [ConvertProgress]/[ConvertDone]/
///    [ConvertFailed] per job.
/// 4. batal lewat [CancelRequest] pada cancel port; selesai batch via [Shutdown].
///
/// Satu worker dipakai untuk SEMUA job — pdfrx membuat internal
/// PdfrxEngineWorker per isolate; spawn/teardown berulang-ulang terbukti
/// crash ("Cannot invoke native callback from a different isolate").
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

/// Jalur PDF: pipeline heuristic existing (PdfrxSource → grouper → classifier),
/// streaming via path (hemat memori).
Future<void> _runPdf(
  SendPort mainPort,
  StartConvert start,
  bool Function() isCancelled,
) async {
  var cancelled = false;
  try {
    final source = await PdfrxSource.open(start.pdfPath);
    try {
      // Phase 1 (reading): histogram — page 0 sebagai penanda.
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
        bodyFontSize: result.stats.bodyFontSize,
        emptyPages: result.stats.emptyPages,
      ));
    } finally {
      // WAJIB: tutup document sebelum job berikutnya — handle native PDFium
      // per-job harus dibebaskan.
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
      message: 'Kesalahan tak terduga: $e',
    ));
  }
}

/// Jalur semantic (non-PDF): extractor pure Dart → markdown streaming.
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
        message: 'Format ${format.label} belum didukung (roadmap Fase 2–3).',
      ));
      return;
    }

    output = FileOutput(start.outputPath);
    final sink = await output.openSink();
    final writer = MarkdownWriter(sink);

    final result = await extractor.extract(
      bytes: null,
      path: start.pdfPath,
      writer: writer,
      onProgress: (done, total) {
        mainPort.send(ConvertProgress(
          jobId: start.jobId,
          page: done,
          total: total,
          elapsedMs: 0,
          phase: 1,
        ));
      },
      isCancelled: () => isCancelled(),
    );

    await writer.close();
    await output.commit();
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
      message: 'Kesalahan tak terduga: $e',
    ));
  }
}
