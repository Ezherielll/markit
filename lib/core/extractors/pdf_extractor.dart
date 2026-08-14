import 'dart:typed_data';

import '../converter.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../output.dart';
import '../pdfrx_source.dart';

/// PDF extractor — thin adapter over the existing two-pass heuristic pipeline
/// ([Converter] + [PdfrxSource]).
///
/// Desktop: streams via [path] (memory-efficient for large documents);
/// web: reads [bytes]. Progress phases: 0 = reading (pass 1), 1 = converting
/// (pass 2). The per-job native PDFium handle is always disposed in a finally
/// block — one persistent worker serves the whole batch (see docs/spike-pdfrx.md).
class PdfExtractor implements FormatExtractor {
  const PdfExtractor();

  @override
  InputFormat get format => InputFormat.pdf;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required OutputTarget output,
    void Function(int done, int total, int phase, int elapsedMs)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final source = bytes != null
        ? await PdfrxSource.openData(
            bytes,
            // Unique per call: web can run several jobs concurrently and
            // pdfrx keys its document cache by sourceName.
            sourceName: 'pdf-${DateTime.now().microsecondsSinceEpoch}',
          )
        : await PdfrxSource.open(path!);
    try {
      // Phase 0 (reading): pass-1 histogram marker.
      onProgress?.call(0, source.pageCount, 0, 0);
      final result = await Converter().convert(
        source: source,
        output: output,
        onProgress: (p) {
          onProgress?.call(p.page, p.total, 1, p.elapsed.inMilliseconds);
        },
        isCancelled: isCancelled,
      );
      return ExtractionResult(
        itemCount: result.pageCount,
        // 1-based: the UI convention (ConvertDone.failedPages).
        failedPages: result.failedPages.map((p) => p + 1).toList(),
        bodyFontSize: result.profile.bodyFontSize,
        emptyPages: result.profile.emptyPages,
        elapsed: result.elapsed,
        outputPath: output is FileOutput ? output.outputPath : null,
      );
    } finally {
      // REQUIRED: close document before next job — per-job native PDFium
      // handle must be freed.
      await source.dispose();
    }
  }
}
