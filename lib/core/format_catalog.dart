import 'dart:typed_data';

import 'extractors/extractor_registry.dart';
import 'input_format.dart';

/// Satu keluarga format dalam katalog: keluarga (enum), daftar ekstensi,
/// dan petunjuk entry ZIP untuk preview teks (lihat [ZipTextPreview]).
class FormatFamily {
  const FormatFamily({
    required this.format,
    required this.extensions,
    this.zipEntryHints = const [],
  });

  final InputFormat format;

  /// Ekstensi tanpa titik, mis. `['doc', 'docx', 'docm']`.
  final List<String> extensions;

  /// Substring nama entry ZIP yang memuat konten utama (docx/pptx/xlsx/
  /// odt/epub) — dipakai [ZipTextPreview] untuk preview cepat tanpa parse
  /// penuh. Kosong untuk format non-ZIP.
  final List<String> zipEntryHints;
}

/// Katalog format — sumber tunggal pengetahuan format.
///
/// Daftar keluarga PERSIS mengikuti daftar "Supported formats" produk
/// (Word, PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV, PDF). Fakta
/// lain diturunkan dari sini: [kDetectableExtensions] (filter picker),
/// deteksi ekstensi di [detectFormat], dan daftar di About.
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

/// Semua ekstensi yang dikenali [detectFormat] — dipakai filter file picker.
/// Diturunkan dari [kFormatCatalog] (sumber tunggal).
final List<String> kDetectableExtensions = [
  for (final family in kFormatCatalog) ...family.extensions,
];

/// True bila format didukung konversi: punya extractor terdaftar (atau
/// jalur PDF existing). Diturunkan dari [ExtractorRegistry] — menambah
/// extractor = otomatis didukung, tanpa edit di sini.
bool isFormatSupported(InputFormat format) =>
    format == InputFormat.pdf ||
    ExtractorRegistry.forFormat(format) != null;

/// True untuk anggota keluarga ZIP+XML (docx/pptx/xlsx/odt/epub) — keluarga
/// yang kontennya bisa di-preview via [ZipTextPreview].
bool isZipBasedFormat(InputFormat format) =>
    format == InputFormat.word ||
    format == InputFormat.powerpoint ||
    format == InputFormat.excel ||
    format == InputFormat.opendocument ||
    format == InputFormat.epub;

/// True untuk ekstensi legacy (OLE2 binary) dalam satu keluarga — terdeteksi
/// & bisa dipilih, tapi belum ada parser (error "not supported yet" yang
/// jelas, bukan gagal "corrupt"). Ditentukan dari nama file (bukan format
/// keluarga) karena satu keluarga menampung format modern + legacy.
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

/// Deteksi format dari nama + konten (magic bytes).
///
/// Prioritas: magic bytes kuat (PDF, ZIP-based, OLE2 legacy, RTF), lalu
/// ekstensi. ZIP-based dibedakan dari ekstensi + inspeksi nama entry ZIP
/// (agar file yang di-rename ekstensinya tetap terdeteksi).
InputFormat detectFormat(String name, Uint8List bytes) {
  if (isUrlName(name)) return InputFormat.unknown;

  final lower = name.toLowerCase();

  if (_startsWith(bytes, [0x25, 0x50, 0x44, 0x46])) {
    return InputFormat.pdf; // %PDF
  }
  if (_startsWith(bytes, [0x50, 0x4B, 0x03, 0x04])) {
    return _detectZipBased(lower, bytes); // PK.. — kontainer ZIP
  }
  if (_startsWith(bytes, [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1])) {
    return _detectOle2(lower); // OLE2 compound file (.doc/.ppt/.xls/.xlsb)
  }
  if (_startsWith(bytes, [0x7B, 0x5C, 0x72, 0x74, 0x66])) {
    return InputFormat.rtf; // {\rtf
  }
  return _detectByExtension(lower);
}

/// Deteksi via ekstensi (nama sudah di-lowercase) — fallback untuk teks dan
/// format tanpa magic bytes.
InputFormat _detectByExtension(String lower) {
  for (final family in kFormatCatalog) {
    for (final ext in family.extensions) {
      if (lower.endsWith('.$ext')) return family.format;
    }
  }
  return InputFormat.unknown;
}

/// Deteksi keluarga ZIP-based: ekstensi tepercaya menang; inspeksi entry ZIP
/// untuk file yang di-rename. Polos (bukan keluarga yang dikenal) → unknown.
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

/// Deteksi OLE2 (legacy binary): hanya ekstensi yang memutuskan keluarga.
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

/// True bila nama terlihat seperti URL (drop dari browser) — butuh jaringan,
/// tidak didukung (NG3: 100% lokal).
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

/// Scan kasar nama entry ZIP pada bytes (local file header menyimpan nama
/// entry di bagian awal archive — cukup tanpa decode penuh).
bool _zipContains(Uint8List bytes, String needle) {
  final ascii = String.fromCharCodes(
    bytes.take(bytes.length > 65536 ? 65536 : bytes.length),
  );
  return ascii.contains(needle);
}
