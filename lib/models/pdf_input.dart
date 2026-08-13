import 'dart:typed_data';

import '../core/input_format.dart';

/// Single conversion input file — platform-agnostic.
///
/// Desktop: [path] points to a file on disk.
/// Web: [bytes] holds file content in memory (no filesystem).
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

  /// File path (desktop); null on web.
  final String? path;

  /// File content (web); null on desktop.
  final Uint8List? bytes;

  /// Detected format during addFiles (magic bytes + extension).
  final InputFormat format;

  bool get isBytes => bytes != null;

  /// Deduplication key: path (desktop) or name+size (web).
  String get dedupeKey => path ?? '$name:$sizeBytes';

  /// Output name: any extension → .md.
  String get outputName => name.replaceFirst(
        RegExp(r'\.\w+$'),
        '.md',
      );
}
