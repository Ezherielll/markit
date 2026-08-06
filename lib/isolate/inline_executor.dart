import 'dart:typed_data';

import '../core/converter.dart';
import '../core/errors.dart';
import '../core/extractors/extractor_registry.dart';
import '../core/input_format.dart';
import '../core/markdown_writer.dart';
import '../core/output.dart';
import '../core/pdfrx_source.dart';
import 'conversion_executor.dart';

/// Eksekusi inline di main isolate (WEB — `Isolate.spawn` tidak didukung).
///
/// Pipeline sudah async per halaman, jadi UI tetap bisa pump antar-await
/// (progress diterima via callback). Keterbatasan: halaman sangat berat bisa
/// menyebabkan jank singkat — acceptable untuk MVP web.
class InlineExecutor implements ConversionExecutor {
  bool _cancelled = false;

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
    _cancelled = false;
    try {
      if (format != InputFormat.pdf) {
        return await _runSemantic(
          jobId: jobId,
          bytes: pdfBytes,
          path: pdfPath,
          outputPath: outputPath,
          format: format,
          onProgress: onProgress,
        );
      }
      final source = pdfBytes != null
          ? await PdfrxSource.openData(pdfBytes, sourceName: jobId)
          : await PdfrxSource.open(pdfPath);
      try {
        final output = MemoryOutput();
        // Phase 1 (reading): histogram — page 0 sebagai penanda.
        onProgress?.call(0, source.pageCount, 0, 0);
        final result = await Converter().convert(
          source: source,
          output: output,
          onProgress: (p) {
            onProgress?.call(
              p.page,
              p.total,
              1,
              p.elapsed.inMilliseconds,
            );
          },
          isCancelled: () => _cancelled,
        );
        return JobExecutionResult(
          success: true,
          pageCount: result.pageCount,
          failedPages: result.failedPages.map((p) => p + 1).toList(),
          bodyFontSize: result.stats.bodyFontSize,
          outputPath: outputPath,
          content: output.content,
        );
      } finally {
        await source.dispose();
      }
    } on ConvertException catch (e) {
      return JobExecutionResult.failure(e.type.name, e.message);
    } catch (e) {
      return JobExecutionResult.failure(
        ConvertError.corrupt.name,
        'Kesalahan tak terduga: $e',
      );
    }
  }

  /// Jalur semantic (web): extractor pure Dart → MemoryOutput.
  ///
  /// Web TIDAK punya filesystem — extractor hanya bisa membaca [bytes].
  /// Bila [bytes] null (mis. drag & drop yang hanya memberi path palsu),
  /// langsung gagal dengan pesan jelas (bukan UnsupportedError → corrupt).
  Future<JobExecutionResult> _runSemantic({
    required String jobId,
    required Uint8List? bytes,
    required String path,
    required String outputPath,
    required InputFormat format,
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  }) async {
    final extractor = ExtractorRegistry.forFormat(format);
    if (extractor == null) {
      return JobExecutionResult.failure(
        'unsupported',
        'Format ${format.label} belum didukung (roadmap Fase 2–3).',
      );
    }
    if (bytes == null) {
      return JobExecutionResult.failure(
        'unsupported',
        'File tidak tersedia di memori (web) — gunakan tombol "Choose files" '
        'atau drag & drop dari folder.',
      );
    }

    final output = MemoryOutput();
    final sink = await output.openSink();
    final writer = MarkdownWriter(sink);

    final result = await extractor.extract(
      bytes: bytes,
      writer: writer,
      onProgress: (done, total) {
        onProgress?.call(done, total, 1, 0);
      },
      isCancelled: () => _cancelled,
    );
    await writer.close();
    await output.commit();

    return JobExecutionResult(
      success: true,
      pageCount: result.itemCount,
      failedPages: const [],
      bodyFontSize: 0,
      outputPath: outputPath,
      content: output.content,
    );
  }

  @override
  void cancel() {
    _cancelled = true;
  }

  @override
  void resetCancel() {
    _cancelled = false;
  }

  @override
  Future<void> shutdown() async {}
}
