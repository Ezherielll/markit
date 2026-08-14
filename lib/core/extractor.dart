import 'dart:typed_data';

import 'input_format.dart';
import 'markdown_writer.dart';
import 'output.dart';

/// Result of extracting one document.
class ExtractionResult {
  ExtractionResult({
    required this.itemCount,
    this.failedPages = const [],
    this.bodyFontSize = 0,
    this.emptyPages = 0,
    this.elapsed = Duration.zero,
    this.outputPath,
    this.warnings = const [],
  });

  /// Item count (paragraph/line/page) — used as the page count in the UI.
  final int itemCount;

  /// Failed pages (1-based, UI convention) — PDF only; empty for semantic.
  final List<int> failedPages;

  /// Body font size (PDF pass-1 profile) — 0 for semantic formats.
  final double bodyFontSize;

  /// Empty pages count (PDF pass-1 profile) — 0 for semantic formats.
  final int emptyPages;

  /// Conversion elapsed time — zero for semantic formats.
  final Duration elapsed;

  /// Path of the written output (FileOutput); null for MemoryOutput/web.
  final String? outputPath;

  final List<String> warnings;
}

/// Abstraction of a per-format extractor.
///
/// The extractor OWNS the output lifecycle: it opens the sink via
/// [ExtractionResult.outputPath] handling, writes, closes, and commits — or
/// aborts on failure. Writer-based (semantic) extractors use
/// [withMarkdownWriter]; the PDF extractor streams through [Converter].
///
/// Contract (error, partial-content, cancel, and progress semantics):
/// - Fatal error (corrupt file) → throw [ConvertException] (batch continues).
/// - Partial content → write as-is + add [ExtractionResult.warnings].
/// - Cancel → [isCancelled] checked per item; stop immediately.
/// - Progress → [onProgress](done, total, phase, elapsedMs) per item; phase
///   0 = reading (pass 1), 1 = converting (pass 2).
abstract class FormatExtractor {
  InputFormat get format;

  /// Extract document content to [output] (streaming).
  ///
  /// [bytes] is always available on web; in the desktop worker, the extractor
  /// reads [path] when [bytes] is null (the PDF path still streams via path).
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required OutputTarget output,
    void Function(int done, int total, int phase, int elapsedMs)? onProgress,
    bool Function()? isCancelled,
  });
}

/// Standard output lifecycle for writer-based (semantic) extraction:
/// opens the sink, runs [run] with the writer, closes + commits on success,
/// aborts and rethrows on failure.
Future<ExtractionResult> withMarkdownWriter(
  OutputTarget output, {
  required Future<ExtractionResult> Function(MarkdownWriter writer) run,
}) async {
  final sink = await output.openSink();
  final writer = MarkdownWriter(sink);
  try {
    final result = await run(writer);
    await writer.close();
    await output.commit();
    return result;
  } catch (_) {
    await output.abort();
    rethrow;
  }
}
