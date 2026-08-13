import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'text_truncate.dart';

/// Text preview result from a ZIP-based document.
class ZipTextPreviewResult {
  const ZipTextPreviewResult({required this.text, required this.truncated});

  final String text;
  final bool truncated;
}

/// FAST text preview for ZIP+XML formats (docx/pptx/xlsx/odt/epub).
///
/// Not a full parser — finds main entry (via hints from format catalog),
/// strips raw XML tags, then truncates. Preview != conversion: sufficient for
/// "Source Preview" without full parse cost.
class ZipTextPreview {
  const ZipTextPreview();

  /// Null if bytes are not a valid ZIP or no entry matches [entryHints]
  /// (e.g. corrupt document).
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

  /// Strip XML tags + unescape entities, placing line breaks on block closes
  /// (Word/ODF/PPT paragraphs, Excel sharedStrings).
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
