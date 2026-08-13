import 'dart:io';

import 'markdown_helpers.dart';

/// Hasil kerja baca file output di background (desktop) — dipakai
/// `compute()` dari DocumentViewer agar UI thread tidak memblok.
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

/// Baca file output, hitung preview terpotong + stats. DIJALANKAN DI
/// ISOLATE (compute) — jangan panggil langsung dari build.
///
/// Parameter berupa record 2 field agar cocok dikirim sebagai pesan
/// `compute(loadDocumentWork, (path: …, maxChars: …))` — fungsi multi-param
/// biasa tidak assignable ke `R Function(M)` dengan M record (Dart 3).
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
