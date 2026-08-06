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
  if (_startsWithBytes(bytes, [0x25, 0x50, 0x44, 0x46])) {
    return InputFormat.pdf; // %PDF
  }
  if (_startsWithBytes(bytes, [0xFF, 0xD8]) ||
      _startsWithBytes(bytes, [0x89, 0x50, 0x4E, 0x47]) ||
      _startsWithBytes(bytes, [0x47, 0x49, 0x46, 0x38]) ||
      _startsWithBytes(bytes, [0x52, 0x49, 0x46, 0x46])) {
    return InputFormat.image;
  }
  if (_startsWithBytes(bytes, [0x49, 0x44, 0x33]) ||
      _startsWithBytes(bytes, [0x4F, 0x67, 0x67, 0x53]) ||
      _startsWithBytes(bytes, [0x66, 0x4C, 0x61, 0x43]) ||
      _startsWithBytes(bytes, [0x52, 0x49, 0x46, 0x46])) {
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
  if (lower.endsWith('.pdf')) return InputFormat.pdf;
  if (lower.endsWith('.txt')) return InputFormat.text;
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
    return InputFormat.markdown;
  }
  if (lower.endsWith('.csv')) return InputFormat.csv;
  if (lower.endsWith('.json')) return InputFormat.json;
  if (lower.endsWith('.xml')) return InputFormat.xml;
  if (lower.endsWith('.html') || lower.endsWith('.htm')) return InputFormat.html;
  if (lower.endsWith('.docx')) return InputFormat.docx;
  if (lower.endsWith('.xlsx')) return InputFormat.xlsx;
  if (lower.endsWith('.pptx')) return InputFormat.pptx;
  if (lower.endsWith('.epub')) return InputFormat.epub;
  if (lower.endsWith('.zip')) return InputFormat.zip;
  if (lower.endsWith('.jpg') ||
      lower.endsWith('.jpeg') ||
      lower.endsWith('.png') ||
      lower.endsWith('.gif') ||
      lower.endsWith('.webp') ||
      lower.endsWith('.bmp') ||
      lower.endsWith('.tiff')) {
    return InputFormat.image;
  }
  if (lower.endsWith('.mp3') ||
      lower.endsWith('.flac') ||
      lower.endsWith('.ogg') ||
      lower.endsWith('.wav') ||
      lower.endsWith('.m4a') ||
      lower.endsWith('.aac')) {
    return InputFormat.audio;
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
