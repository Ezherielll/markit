import 'dart:typed_data';

/// Jenis format input yang didukung MarkIt.
///
/// Fase 1 (teks/markup) sudah punya extractor; DOCX/XLSX/PPTX/EPUB/ZIP
/// dan Image/Audio masuk roadmap Fase 2–3 (deteksi tetap disediakan agar
/// UI & error message akurat sejak awal).
enum InputFormat {
  pdf,
  text,
  markdown,
  csv,
  json,
  xml,
  html,
  docx,
  xlsx,
  pptx,
  epub,
  zip,
  image,
  audio,
  unknown;

  bool get isSupported => this == pdf || this == text || this == markdown ||
      this == csv || this == json || this == xml || this == html;

  String get label => switch (this) {
        pdf => 'PDF',
        text => 'Text',
        markdown => 'Markdown',
        csv => 'CSV',
        json => 'JSON',
        xml => 'XML',
        html => 'HTML',
        docx => 'DOCX',
        xlsx => 'XLSX',
        pptx => 'PPTX',
        epub => 'EPUB',
        zip => 'ZIP',
        image => 'Image',
        audio => 'Audio',
        unknown => 'Unknown',
      };
}

/// Deteksi format dari nama + konten (magic bytes).
///
/// Prioritas: magic bytes untuk kontainer (PDF/ZIP-based/image/audio),
/// lalu ekstensi untuk teks. ZIP-based (docx/xlsx/pptx/epub) dibedakan
/// dari ekstensi + inspeksi nama entry ZIP (agar file yang di-rename
/// ekstensinya tetap terdeteksi — plan §4.2).
InputFormat detectFormat(String name, Uint8List bytes) {
  if (isUrlName(name)) return InputFormat.unknown;

  final lower = name.toLowerCase();
  final trimmed = _trimLeadingWhitespace(bytes);

  // Magic bytes kuat — diutamakan dari ekstensi.
  final byContent = _detectByContent(bytes, trimmed, lower);
  if (byContent != null) return byContent;

  return _detectByExtension(lower);
}

/// Deteksi via konten (magic bytes + karakter awal). Null bila tidak ada
/// kecocokan konten (lanjut ke ekstensi).
InputFormat? _detectByContent(Uint8List bytes, List<int> trimmed, String lower) {
  if (_startsWithBytes(bytes, [0x25, 0x50, 0x44, 0x46])) {
    return InputFormat.pdf; // %PDF
  }
  if (_startsWithBytes(bytes, [0xFF, 0xD8]) ||
      _startsWithBytes(bytes, [0x89, 0x50, 0x4E, 0x47]) ||
      _startsWithBytes(bytes, [0x47, 0x49, 0x46, 0x38]) ||
      _startsWithBytes(bytes, [0x52, 0x49, 0x46, 0x46])) {
    // RIFF ambigu: WAV (audio) vs WEBP/AVI (image/video) — ekstensi memutuskan.
    return lower.endsWith('.wav') ? InputFormat.audio : InputFormat.image;
  }
  if (_startsWithBytes(bytes, [0x49, 0x44, 0x33]) ||
      _startsWithBytes(bytes, [0x4F, 0x67, 0x67, 0x53]) ||
      _startsWithBytes(bytes, [0x66, 0x4C, 0x61, 0x43])) {
    return InputFormat.audio;
  }
  if (_startsWithBytes(bytes, [0x50, 0x4B, 0x03, 0x04])) {
    return _detectZipBased(lower, bytes);
  }

  // JSON: `{` atau `[` setelah whitespace.
  if (trimmed.isNotEmpty) {
    final c = trimmed[0];
    if (c == 0x7B || c == 0x5B) return InputFormat.json;
    if (c == 0x3C) return _detectMarkup(lower, bytes);
  }
  return null;
}

/// Tabel ekstensi → format (urutan = prioritas original; ekstensi saling
/// eksklusif sehingga urutan tidak mengubah hasil).
const _extensionRules = <(String, InputFormat)>[
  ('pdf', InputFormat.pdf),
  ('txt', InputFormat.text),
  ('md', InputFormat.markdown),
  ('markdown', InputFormat.markdown),
  ('csv', InputFormat.csv),
  ('json', InputFormat.json),
  ('xml', InputFormat.xml),
  ('html', InputFormat.html),
  ('htm', InputFormat.html),
  ('docx', InputFormat.docx),
  ('xlsx', InputFormat.xlsx),
  ('pptx', InputFormat.pptx),
  ('epub', InputFormat.epub),
  ('zip', InputFormat.zip),
  ('jpg', InputFormat.image),
  ('jpeg', InputFormat.image),
  ('png', InputFormat.image),
  ('gif', InputFormat.image),
  ('webp', InputFormat.image),
  ('bmp', InputFormat.image),
  ('tiff', InputFormat.image),
  ('mp3', InputFormat.audio),
  ('flac', InputFormat.audio),
  ('ogg', InputFormat.audio),
  ('wav', InputFormat.audio),
  ('m4a', InputFormat.audio),
  ('aac', InputFormat.audio),
];

/// Semua ekstensi yang dikenali [detectFormat] — dipakai filter file picker
/// agar format non-teks (DOCX/XLSX/PPTX/EPUB/ZIP/image/audio) tetap bisa
/// dipilih dari dialog (lalu ditolak dengan pesan "not supported yet",
/// bukan gagal "corrupt" saat dibaca). Sumber tunggal: [_extensionRules].
final List<String> kDetectableExtensions = [
  for (final (ext, _) in _extensionRules) ext,
];

/// Deteksi via ekstensi (nama sudah di-lowercase) — fallback untuk teks
/// dan format tanpa magic bytes.
InputFormat _detectByExtension(String lower) {
  for (final (ext, format) in _extensionRules) {
    if (lower.endsWith('.$ext')) return format;
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

/// Baca karakter pertama non-whitespace sebagai int.
List<int> _trimLeadingWhitespace(Uint8List bytes) {
  var i = 0;
  while (i < bytes.length && _isWhitespace(bytes[i])) {
    i++;
  }
  return i < bytes.length ? [bytes[i]] : const [];
}

bool _isWhitespace(int b) =>
    b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D;

bool _startsWithBytes(Uint8List bytes, List<int> magic) {
  if (bytes.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (bytes[i] != magic[i]) return false;
  }
  return true;
}

InputFormat _detectZipBased(String lower, Uint8List bytes) {
  // Ekstensi tepercaya menang; inspeksi konten untuk file yang di-rename.
  if (lower.endsWith('.docx') || _zipContains(bytes, 'word/')) {
    return InputFormat.docx;
  }
  if (lower.endsWith('.xlsx') || _zipContains(bytes, 'xl/')) {
    return InputFormat.xlsx;
  }
  if (lower.endsWith('.pptx') || _zipContains(bytes, 'ppt/')) {
    return InputFormat.pptx;
  }
  if (lower.endsWith('.epub') || _zipContains(bytes, 'mimetype')) {
    return InputFormat.epub;
  }
  if (lower.endsWith('.zip')) return InputFormat.zip;
  return InputFormat.zip;
}

/// Deteksi markup dimulai `<`: XML (`<?xml`) vs HTML (`<!DOCTYPE html`/`<html`).
/// Ekstensi jadi tiebreaker untuk file yang content-nya generik `<...>`.
InputFormat _detectMarkup(String lower, Uint8List bytes) {
  final ascii = String.fromCharCodes(
    bytes.take(bytes.length > 1024 ? 1024 : bytes.length),
  );
  final head = ascii.trimLeft().toLowerCase();
  if (head.startsWith('<?xml')) return InputFormat.xml;
  if (head.startsWith('<!doctype html') || head.startsWith('<html')) {
    return InputFormat.html;
  }
  if (lower.endsWith('.xml')) return InputFormat.xml;
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return InputFormat.html;
  return InputFormat.xml;
}

/// Scan kasar nama entry ZIP pada bytes (local file header menyimpan nama
/// entry di bagian awal archive — cukup untuk M1, tanpa decode penuh).
bool _zipContains(Uint8List bytes, String needle) {
  final ascii = String.fromCharCodes(
    bytes.take(bytes.length > 65536 ? 65536 : bytes.length),
  );
  return ascii.contains(needle);
}
