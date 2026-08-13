import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  final raw = await _readAll(input);
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

/// Preview keluarga ZIP+XML: cari entry utama via petunjuk katalog format,
/// strip tag, truncate. ZIP valid tanpa entry yang dikenal → [SourceLoadException].
Future<SourceText> _loadZipPreview(
  PdfInput input, {
  required int maxChars,
}) async {
  final raw = await _readAll(input);
  final family = kFormatCatalog.firstWhere((f) => f.format == input.format);
  final preview = const ZipTextPreview().extract(
    raw,
    entryHints: family.zipEntryHints,
    maxChars: maxChars,
  );
  if (preview == null) {
    throw const SourceLoadException(
      'The file has no recognizable content entry.',
    );
  }
  return SourceText(content: preview.text, truncated: preview.truncated);
}

Future<Uint8List> _readAll(PdfInput input) async {
  final bytes = input.bytes;
  if (bytes != null) return bytes;
  final path = input.path;
  if (path == null) throw const SourceLoadException('no bytes or path');
  try {
    return await File(path).readAsBytes();
  } on FileSystemException catch (e) {
    throw SourceLoadException(e.message);
  }
}
