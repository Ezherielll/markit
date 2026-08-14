import 'dart:typed_data';

import '../core/converter.dart';
import '../core/errors.dart';
import '../core/extractors/extractor_registry.dart';
import '../core/input_format.dart';
import '../core/output.dart';
import '../core/pdfrx_source.dart';
import 'conversion_executor.dart';

/// Inline execution on main isolate (WEB — `Isolate.spawn` not supported).
///
/// Pipeline is already async per page, so UI can pump between awaits
/// (progress received via callback). Limitation: heavy pages may cause
/// minor jank — acceptable for web.
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
        // Phase 1 (reading): histogram — page 0 marker.
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
          bodyFontSize: result.profile.bodyFontSize,
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
        'Unexpected error: $e',
      );
    }
  }

  /// Semantic path (web): pure Dart extractor → MemoryOutput.
  ///
  /// Web DOES NOT have a filesystem — extractor can only read [bytes].
  /// If [bytes] is null (e.g. drag & drop giving dummy path),
  /// fails immediately with a clear error message.
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
        'Format ${format.label} is not yet supported for conversion.',
      );
    }
    if (bytes == null) {
      return JobExecutionResult.failure(
        'unsupported',
        'File data not available in memory (web) — use "Choose Files" '
        'or drag & drop files directly.',
      );
    }

    final output = MemoryOutput();

    final result = await extractor.extract(
      bytes: bytes,
      output: output,
      onProgress: onProgress,
      isCancelled: () => _cancelled,
    );

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
