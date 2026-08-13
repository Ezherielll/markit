import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:markit/core/format_catalog.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/core/text_truncate.dart';
import 'package:markit/core/zip_text_preview.dart';
import 'package:markit/models/pdf_input.dart';

/// Source text preview cap: 1 MiB — more generous than markdown preview
/// (64 KiB) because raw source files may need full inspection.
const int maxSourceChars = 1024 * 1024;

/// Source data ready for rendering.
sealed class SourceData {
  const SourceData();
}

/// Raw text (CSV/RTF or [ZipTextPreview] result for ZIP+XML formats) —
/// preview truncated.
class SourceText extends SourceData {
  const SourceText({required this.content, required this.truncated});

  final String content;
  final bool truncated;
}

/// PDF — file path (desktop) or bytes (web).
class SourcePdf extends SourceData {
  const SourcePdf({this.path, this.bytes});

  final String? path;
  final Uint8List? bytes;
}

/// Format detected but cannot be previewed yet (legacy OLE2 / unknown).
class SourceUnsupportedException implements Exception {
  const SourceUnsupportedException();
}

/// Failed to read source (file missing / no bytes or path).
class SourceLoadException implements Exception {
  const SourceLoadException(this.message);

  final String message;
}

/// Load [PdfInput] as [SourceData] according to detected format.
///
/// PDF → [SourcePdf] (processed by viewer); ZIP+XML family → [SourceText]
/// via [ZipTextPreview] (main entry raw text, without full parse);
/// CSV/RTF → [SourceText] (tolerant UTF-8 decode + preview truncate).
/// Legacy OLE2 (.doc/.ppt/.pps/.pot/.xls/.xlsb) & unknown → unsupported.
Future<SourceData> loadSource(
  PdfInput input, {
  int maxChars = maxSourceChars,
}) async {
  if (input.format == InputFormat.unknown) {
    throw const SourceUnsupportedException();
  }
  if (isLegacyFormatExtension(input.format, input.name)) {
    throw const SourceUnsupportedException();
  }
  return switch (input.format) {
    InputFormat.pdf => loadSourcePdf(input),
    InputFormat.word ||
    InputFormat.powerpoint ||
    InputFormat.excel ||
    InputFormat.opendocument ||
    InputFormat.epub => _loadZipPreview(input, maxChars: maxChars),
    InputFormat.csv || InputFormat.rtf =>
      loadSourceText(input, maxChars: maxChars),
    InputFormat.unknown => throw const SourceUnsupportedException(),
  };
}

Future<SourceText> loadSourceText(
  PdfInput input, {
  int maxChars = maxSourceChars,
}) async {
  // Read ONLY preview window (maxChars * 4 + 8 bytes) — source file can
  // be hundreds of MB; full decode on UI thread blocks. Window = maxChars * 4
  // BECAUSE maxChars is in CHARACTERS and UTF-8 max 4 bytes/char:
  // 4x guarantees maxChars-th character is intact within window, so
  // truncate result is byte-for-byte identical to full decode; +8 margin.
  final raw = await _readPreviewWindow(input, maxChars * 4 + 8);
  final content = utf8.decode(raw, allowMalformed: true);
  final cut = truncateText(content, maxChars: maxChars);
  return SourceText(content: cut.preview, truncated: cut.truncated);
}

Future<SourcePdf> loadSourcePdf(PdfInput input) async {
  final bytes = input.bytes;
  if (bytes != null) return SourcePdf(bytes: bytes);
  final path = input.path;
  if (path != null) return SourcePdf(path: path);
  throw const SourceLoadException('no bytes or path');
}

/// Zip preview worker arguments — passed to isolate via compute.
class _ZipPreviewArgs {
  const _ZipPreviewArgs({
    required this.path,
    required this.bytes,
    required this.entryHints,
    required this.maxChars,
  });

  final String? path;
  final Uint8List? bytes;
  final List<String> entryHints;
  final int maxChars;
}

/// Zip preview worker result (isolate). [error] non-null = read/parse failed.
class _ZipPreviewResult {
  const _ZipPreviewResult({this.error, this.content, this.truncated = false});

  final String? error;
  final String? content;
  final bool truncated;
}

_ZipPreviewResult _zipPreviewWorker(_ZipPreviewArgs args) {
  final Uint8List? raw;
  try {
    if (args.bytes != null && args.bytes!.isNotEmpty) {
      raw = args.bytes;
    } else if (args.path != null) {
      final file = File(args.path!);
      if (!file.existsSync()) {
        return const _ZipPreviewResult(error: 'file not found');
      }
      raw = file.readAsBytesSync();
    } else {
      return const _ZipPreviewResult(error: 'no bytes or path');
    }
  } on FileSystemException {
    return const _ZipPreviewResult(error: 'file not found');
  }

  final preview = ZipTextPreview().extract(
    raw!,
    entryHints: args.entryHints,
    maxChars: args.maxChars,
  );
  if (preview == null) {
    return const _ZipPreviewResult(error: 'no recognizable content entry');
  }
  return _ZipPreviewResult(
    content: preview.text,
    truncated: preview.truncated,
  );
}

/// ZIP+XML family preview: find main entry via format catalog hints,
/// strip tags, truncate. Valid ZIP without recognized entry → [SourceLoadException].
Future<SourceText> _loadZipPreview(
  PdfInput input, {
  required int maxChars,
}) async {
  final family = kFormatCatalog.firstWhere((f) => f.format == input.format);
  // Read + decode ZIP + strip tags IN ISOLATE (desktop); web inline — UI
  // thread does not block for large files.
  final result = await compute(
    _zipPreviewWorker,
    _ZipPreviewArgs(
      path: input.path,
      bytes: input.bytes,
      entryHints: family.zipEntryHints,
      maxChars: maxChars,
    ),
  );
  if (result.error != null) {
    throw SourceLoadException(result.error!);
  }
  return SourceText(content: result.content!, truncated: result.truncated);
}

/// Read at most [windowBytes] bytes from file start (desktop: window
/// read via RandomAccessFile; web: bytes sublist) — preview does not need
/// full content. Window sufficiently large (maxChars * 4 + 8) so preview
/// is identical to full decode truncate for ALL UTF-8 content.
Future<Uint8List> _readPreviewWindow(PdfInput input, int windowBytes) async {
  final bytes = input.bytes;
  if (bytes != null) {
    if (bytes.length <= windowBytes) return bytes;
    return Uint8List.sublistView(bytes, 0, windowBytes);
  }
  final path = input.path;
  if (path == null) throw const SourceLoadException('no bytes or path');
  try {
    final file = File(path);
    final length = await file.length();
    if (length <= windowBytes) return await file.readAsBytes();
    final raf = await file.open();
    try {
      return await raf.read(windowBytes);
    } finally {
      await raf.close();
    }
  } on FileSystemException catch (e) {
    throw SourceLoadException(e.message);
  }
}
