import 'dart:typed_data';

import '../core/input_format.dart';

/// Satu file input konversi — platform-agnostic.
///
/// Desktop: [path] mengarah ke file di disk.
/// Web: [bytes] memuat konten file di memory (tidak ada filesystem).
class PdfInput {
  const PdfInput({
    required this.name,
    this.sizeBytes,
    this.path,
    this.bytes,
    this.format = InputFormat.pdf,
  });

  final String name;
  final int? sizeBytes;

  /// Path file (desktop); null di web.
  final String? path;

  /// Konten file (web); null di desktop.
  final Uint8List? bytes;

  /// Format terdeteksi saat addFiles (magic bytes + ekstensi).
  final InputFormat format;

  bool get isBytes => bytes != null;

  /// Kunci dedupe: path (desktop) atau nama+ukuran (web).
  String get dedupeKey => path ?? '$name:$sizeBytes';

  /// Nama output: ekstensi apa pun → .md.
  String get outputName => name.replaceFirst(
        RegExp(r'\.\w+$'),
        '.md',
      );
}
