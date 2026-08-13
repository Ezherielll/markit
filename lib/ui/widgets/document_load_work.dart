import 'dart:io';

import 'markdown_helpers.dart';

/// Result of loading output file in background (desktop) — used
/// by `compute()` from DocumentViewer so UI thread does not block.
class DocumentLoadResult {
  const DocumentLoadResult({
    required this.content,
    required this.preview,
    required this.truncated,
    required this.stats,
  });

  final String content;
  final String preview;
  final bool truncated;
  final MdStats stats;
}

/// Read output file, compute truncated preview + stats. EXECUTED IN
/// ISOLATE (compute) — do not call directly from build.
///
/// Parameter is a 2-field record so it matches
/// `compute(loadDocumentWork, (path: …, maxChars: …))` — ordinary multi-param
/// functions are not assignable to `R Function(M)` with M record in Dart 3.
DocumentLoadResult loadDocumentWork(({String path, int maxChars}) args) {
  final path = args.path;
  final maxChars = args.maxChars;
  final file = File(path);
  if (!file.existsSync()) {
    throw FileSystemException('File not found', path);
  }
  final content = file.readAsStringSync();
  final cut = truncateMarkdownPreview(content, maxChars: maxChars);
  return DocumentLoadResult(
    content: content,
    preview: cut.preview,
    truncated: cut.truncated,
    stats: computeMdStats(content),
  );
}
