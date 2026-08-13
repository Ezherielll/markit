import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'text_truncate.dart';

/// Hasil preview teks dari dokumen berbasis ZIP.
class ZipTextPreviewResult {
  const ZipTextPreviewResult({required this.text, required this.truncated});

  final String text;
  final bool truncated;
}

/// Preview teks CEPAT untuk format ZIP+XML (docx/pptx/xlsx/odt/epub).
///
/// Bukan parser — hanya cari entry utama (via petunjuk dari katalog format),
/// strip tag XML kasar, lalu truncate. Preview ≠ konversi: cukup untuk
/// "Source Preview" tanpa biaya parse penuh.
class ZipTextPreview {
  const ZipTextPreview();

  /// Null bila bytes bukan ZIP yang valid atau tidak ada entry yang cocok
  /// dengan [entryHints] (mis. dokumen rusak).
  ZipTextPreviewResult? extract(
    Uint8List bytes, {
    required List<String> entryHints,
    int maxChars = 1024 * 1024,
  }) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } on ArchiveException {
      return null;
    }

    String? raw;
    for (final hint in entryHints) {
      final entry = archive.files
          .where((f) => f.isFile && f.name.toLowerCase().contains(hint))
          .firstOrNull;
      if (entry == null) continue;
      raw = utf8.decode(entry.content as List<int>, allowMalformed: true);
      break;
    }
    if (raw == null) return null;

    final text = _stripMarkup(raw);
    final cut = truncateText(text, maxChars: maxChars);
    return ZipTextPreviewResult(text: cut.preview, truncated: cut.truncated);
  }

  /// Strip tag XML + unescape entity, dengan pemisah baris pada penutup
  /// blok teks umum (paragraf Word/ODF/PPT, sharedString Excel).
  String _stripMarkup(String xml) {
    final withBreaks = xml.replaceAll(
      RegExp(r'</(?:w:p|text:p|a:p|p:sp|si|h\d)>', caseSensitive: false),
      '\n',
    );
    final noTags = withBreaks.replaceAll(RegExp(r'<[^>]*>'), '');
    final unescaped = noTags
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&');
    return unescaped
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .join('\n');
  }
}
