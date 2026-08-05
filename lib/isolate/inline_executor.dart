import 'dart:typed_data';

import '../core/converter.dart';
import '../core/errors.dart';
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
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  }) async {
    _cancelled = false;
    try {
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
