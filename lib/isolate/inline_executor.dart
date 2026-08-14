import 'dart:typed_data';

import '../core/errors.dart';
import '../core/extractors/extractor_registry.dart';
import '../core/input_format.dart';
import '../core/output.dart';
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
      final extractor = ExtractorRegistry.forFormat(format);
      if (extractor == null) {
        return JobExecutionResult.failure(
          'unsupported',
          'Format ${format.label} is not yet supported for conversion.',
        );
      }
      if (pdfBytes == null) {
        // Web has NO filesystem — every format (PDF included) needs bytes.
        // A null payload (e.g. drag & drop giving a dummy path) fails with a
        // clear message instead of a generic corrupt error.
        return JobExecutionResult.failure(
          'unsupported',
          'File data not available in memory (web) — use "Choose Files" '
          'or drag & drop files directly.',
        );
      }

      final output = MemoryOutput();
      final result = await extractor.extract(
        bytes: pdfBytes,
        path: pdfPath,
        output: output,
        onProgress: onProgress,
        isCancelled: () => _cancelled,
      );
      return JobExecutionResult(
        success: true,
        pageCount: result.itemCount,
        failedPages: result.failedPages,
        bodyFontSize: result.bodyFontSize,
        outputPath: outputPath,
        content: output.content,
      );
    } on ConvertException catch (e) {
      return JobExecutionResult.failure(e.type.name, e.message);
    } catch (e) {
      return JobExecutionResult.failure(
        ConvertError.corrupt.name,
        'Unexpected error: $e',
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
