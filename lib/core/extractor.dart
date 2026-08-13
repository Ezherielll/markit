import 'dart:typed_data';

import 'input_format.dart';
import 'markdown_writer.dart';

/// Result of extracting a single non-PDF document.
class ExtractionResult {
  ExtractionResult({required this.itemCount, this.warnings = const []});

  /// Item count (paragraph/line/slide) — used as the page count in the UI.
  final int itemCount;
  final List<String> warnings;
}

/// Abstraction of a per-format extractor (pure Dart, no FFI — runs offline
/// on desktop & web).
///
/// Contract (error, partial-content, cancel, and progress semantics):
/// - Fatal error (corrupt file) → throw [ConvertException] (batch continues).
/// - Partial content → write as-is + add [ExtractionResult.warnings].
/// - Cancel → [isCancelled] checked per item; stop immediately.
/// - Progress → [onProgress](done, total) per item (paragraph/line/slide).
abstract class FormatExtractor {
  InputFormat get format;

  /// Extract document content → markdown block via [writer] (streaming).
  ///
  /// [bytes] is always available on web; in the desktop worker, the extractor
  /// reads [path] when [bytes] is null (the PDF path still streams via path).
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  });
}
