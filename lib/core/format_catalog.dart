import 'dart:typed_data';

import 'extractors/extractor_registry.dart';
import 'input_format.dart';

/// A single format family in the catalog: family (enum), list of extensions,
/// and ZIP entry hints for text preview (see [ZipTextPreview]).
class FormatFamily {
  const FormatFamily({
    required this.format,
    required this.extensions,
    this.zipEntryHints = const [],
  });

  final InputFormat format;

  /// Extensions without dot, e.g. `['doc', 'docx', 'docm']`.
  final List<String> extensions;

  /// Substring of ZIP entry names containing main content (docx/pptx/xlsx/
  /// odt/epub) — used by [ZipTextPreview] for fast preview without
  /// full parsing. Empty for non-ZIP formats.
  final List<String> zipEntryHints;
}

/// Format catalog — single source of truth for format knowledge.
///
/// Family list EXACTLY matches product "Supported formats"
/// (Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV, PDF). Other facts
/// are derived from here: [kDetectableExtensions] (picker filter),
/// extension detection in [detectFormat], and list in About screen.
const List<FormatFamily> kFormatCatalog = [
  FormatFamily(
    format: InputFormat.word,
    extensions: ['doc', 'docx', 'docm'],
    zipEntryHints: ['word/document.xml'],
  ),
  FormatFamily(
    format: InputFormat.powerpoint,
    extensions: ['ppt', 'pps', 'pot', 'pptx', 'pptm', 'ppsx', 'ppsm'],
    zipEntryHints: ['ppt/slides/slide', 'ppt/slides/'],
  ),
  FormatFamily(
    format: InputFormat.excel,
    extensions: ['xls', 'xlsx', 'xlsm', 'xlsb'],
    zipEntryHints: ['xl/sharedStrings.xml', 'xl/worksheets/sheet'],
  ),
  FormatFamily(
    format: InputFormat.opendocument,
    extensions: ['odt', 'ods', 'odp'],
    zipEntryHints: ['content.xml'],
  ),
  FormatFamily(format: InputFormat.rtf, extensions: ['rtf']),
  FormatFamily(format: InputFormat.epub, extensions: ['epub'], zipEntryHints: [
    '.xhtml',
    '.html',
  ]),
  FormatFamily(format: InputFormat.csv, extensions: ['csv']),
  FormatFamily(format: InputFormat.pdf, extensions: ['pdf']),
];

/// All extensions recognized by [detectFormat] — used for file picker filter.
/// Derived from [kFormatCatalog] (single source of truth).
final List<String> kDetectableExtensions = [
  for (final family in kFormatCatalog) ...family.extensions,
];

/// True if format is supported for conversion: has registered extractor (or
/// existing PDF path). Derived from [ExtractorRegistry] — adding an
/// extractor automatically enables support without editing here.
bool isFormatSupported(InputFormat format) =>
    format == InputFormat.pdf ||
    ExtractorRegistry.forFormat(format) != null;

/// True for members of ZIP+XML family (docx/pptx/xlsx/odt/epub) — families
/// whose content can be previewed via [ZipTextPreview].
bool isZipBasedFormat(InputFormat format) =>
    format == InputFormat.word ||
    format == InputFormat.powerpoint ||
    format == InputFormat.excel ||
    format == InputFormat.opendocument ||
    format == InputFormat.epub;

/// True for legacy extensions (OLE2 binary) in a family — detected
/// & selectable, but no parser available yet (clear "not supported yet"
/// error, not a "corrupt" failure). Determined from file name (not family
/// format) because a family holds both modern + legacy formats.
bool isLegacyFormatExtension(InputFormat format, String name) {
  final lower = name.toLowerCase();
  return switch (format) {
    InputFormat.word => lower.endsWith('.doc'),
    InputFormat.powerpoint =>
      lower.endsWith('.ppt') || lower.endsWith('.pps') || lower.endsWith('.pot'),
    InputFormat.excel =>
      lower.endsWith('.xls') || lower.endsWith('.xlsb'),
    _ => false,
  };
}

/// Detect format from name + content (magic bytes).
///
/// Priority: strong magic bytes (PDF, ZIP-based, OLE2 legacy, RTF), then
/// extension. ZIP-based distinguished by extension + ZIP entry name inspection
/// (so renamed files are still detected correctly).
InputFormat detectFormat(String name, Uint8List bytes) {
  if (isUrlName(name)) return InputFormat.unknown;

  final lower = name.toLowerCase();

  if (_startsWith(bytes, [0x25, 0x50, 0x44, 0x46])) {
    return InputFormat.pdf; // %PDF
  }
  if (_startsWith(bytes, [0x50, 0x4B, 0x03, 0x04])) {
    return _detectZipBased(lower, bytes); // PK.. — ZIP container
  }
  if (_startsWith(bytes, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
    return _detectOle2(lower); // OLE2 compound file (.doc/.ppt/.xls/.xlsb)
  }
  if (_startsWith(bytes, [0x7B, 0x5C, 0x72, 0x74, 0x66])) {
    return InputFormat.rtf; // {\rtf
  }
  return _detectByExtension(lower);
}

/// Detect via extension (name already lowercased) — fallback for text and
/// formats without magic bytes.
InputFormat _detectByExtension(String lower) {
  for (final family in kFormatCatalog) {
    for (final ext in family.extensions) {
      if (lower.endsWith('.$ext')) return family.format;
    }
  }
  return InputFormat.unknown;
}

/// Detect ZIP-based family: trusted extension wins; inspect ZIP entries
/// for renamed files. Plain ZIP (not a known family) → unknown.
InputFormat _detectZipBased(String lower, Uint8List bytes) {
  final byExt = _detectByExtension(lower);
  if (isZipBasedFormat(byExt)) return byExt;
  if (_zipContains(bytes, 'word/')) return InputFormat.word;
  if (_zipContains(bytes, 'ppt/')) return InputFormat.powerpoint;
  if (_zipContains(bytes, 'xl/')) return InputFormat.excel;
  if (_zipContains(bytes, 'content.xml')) return InputFormat.opendocument;
  if (_zipContains(bytes, 'mimetypeapplication/vnd.oasis.opendocument')) {
    return InputFormat.opendocument;
  }
  if (_zipContains(bytes, 'mimetype')) return InputFormat.epub;
  return InputFormat.unknown;
}

/// Detect OLE2 (legacy binary): extension alone decides family.
InputFormat _detectOle2(String lower) {
  if (lower.endsWith('.doc')) return InputFormat.word;
  if (lower.endsWith('.ppt') ||
      lower.endsWith('.pps') ||
      lower.endsWith('.pot')) {
    return InputFormat.powerpoint;
  }
  if (lower.endsWith('.xls') || lower.endsWith('.xlsb')) {
    return InputFormat.excel;
  }
  return InputFormat.unknown;
}

/// True if name looks like a URL (dropped from browser) — requires network,
/// unsupported (100% local).
bool isUrlName(String name) {
  final lower = name.toLowerCase();
  return lower.startsWith('http://') ||
      lower.startsWith('https://') ||
      lower.startsWith('www.');
}

bool _startsWith(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

/// Rough scan of ZIP entry names in bytes (local file header stores entry
/// names near start of archive — sufficient without full decode).
bool _zipContains(Uint8List bytes, String needle) {
  final ascii = String.fromCharCodes(
    bytes.take(bytes.length > 65536 ? 65536 : bytes.length),
  );
  return ascii.contains(needle);
}
