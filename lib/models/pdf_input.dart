import 'dart:typed_data';

/// Satu file PDF sebagai input konversi — platform-agnostic.
///
/// Desktop: [path] mengarah ke file di disk.
/// Web: [bytes] memuat konten file di memory (tidak ada filesystem).
class PdfInput {
  const PdfInput({
    required this.name,
    this.sizeBytes,
    this.path,
    this.bytes,
  });

  final String name;
  final int? sizeBytes;

  /// Path file (desktop); null di web.
  final String? path;

  /// Konten file (web); null di desktop.
  final Uint8List? bytes;

  bool get isBytes => bytes != null;

  /// Kunci dedupe: path (desktop) atau nama+ukuran (web).
  String get dedupeKey => path ?? '$name:$sizeBytes';

  String get outputName => name.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '.md',
      );
}
