import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:markit/core/format_catalog.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/core/text_truncate.dart';
import 'package:markit/core/zip_text_preview.dart';
import 'package:markit/models/pdf_input.dart';

/// Cap preview teks sumber: 1 MiB — lebih longgar dari preview markdown
/// (64 KiB) karena ini file sumber mentah yang perlu diperiksa utuh.
const int maxSourceChars = 1024 * 1024;

/// Data sumber yang siap dirender.
sealed class SourceData {
  const SourceData();
}

/// Teks mentah (CSV/RTF atau hasil [ZipTextPreview] untuk format ZIP+XML) —
/// sudah dipotong preview.
class SourceText extends SourceData {
  const SourceText({required this.content, required this.truncated});

  final String content;
  final bool truncated;
}

/// PDF — referensi file (desktop) atau bytes (web).
class SourcePdf extends SourceData {
  const SourcePdf({this.path, this.bytes});

  final String? path;
  final Uint8List? bytes;
}

/// Format terdeteksi tapi belum bisa di-preview (legacy OLE2 / unknown).
class SourceUnsupportedException implements Exception {
  const SourceUnsupportedException();
}

/// Gagal membaca sumber (file hilang / tidak ada bytes maupun path).
class SourceLoadException implements Exception {
  const SourceLoadException(this.message);

  final String message;
}

/// Muat [PdfInput] sebagai [SourceData] sesuai format terdeteksinya.
///
/// PDF → [SourcePdf] (diproses viewer); keluarga ZIP+XML → [SourceText]
/// via [ZipTextPreview] (teks mentah entry utama, tanpa parse penuh);
/// CSV/RTF → [SourceText] (decode UTF-8 toleran + potong preview).
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
  // Baca HANYA window preview (maxChars × 4 + 8 byte) — file sumber bisa
  // ratusan MB; decode penuh di UI thread memblok. Window = maxChars×4
  // KARENA maxChars dihitung dalam KARAKTER dan UTF-8 maks 4 byte/karakter:
  // 4× menjamin karakter ke-maxChars selalu utuh di dalam window, sehingga
  // hasil truncate identik byte-per-byte dengan decode penuh; +8 margin.
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

/// Argumen kerja zip preview — dikirim ke isolate via compute.
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

/// Hasil kerja zip preview (isolate). [error] non-null = gagal baca/parse.
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

/// Preview keluarga ZIP+XML: cari entry utama via petunjuk katalog format,
/// strip tag, truncate. ZIP valid tanpa entry yang dikenal → [SourceLoadException].
Future<SourceText> _loadZipPreview(
  PdfInput input, {
  required int maxChars,
}) async {
  final family = kFormatCatalog.firstWhere((f) => f.format == input.format);
  // Baca + decode ZIP + strip tag DI ISOLATE (desktop); web inline — UI
  // thread tidak memblok untuk file besar.
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

/// Baca paling banyak [windowBytes] byte dari awal file (desktop: window
/// read via RandomAccessFile; web: sublist bytes) — preview tidak butuh
/// seluruh isi. Window cukup besar (maxChars × 4 + 8) agar preview
/// identik dengan truncate atas decode penuh untuk SEMUA konten UTF-8.
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
