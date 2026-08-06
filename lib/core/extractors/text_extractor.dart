import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_writer.dart';
import '../../models/layout.dart';

/// Ekstraktor teks polos & markdown (passthrough).
///
/// - `.txt`: deteksi encoding (UTF-8, fallback latin1), BOM strip,
///   baris kosong = pemisah paragraf.
/// - `.md`/`.markdown`: passthrough — isi ditulis apa adanya.
class TextExtractor implements FormatExtractor {
  const TextExtractor();

  @override
  InputFormat get format => InputFormat.markdown;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final content = _readContent(bytes, path);
    if (content == null) {
      throw ConvertException(
        ConvertError.corrupt,
        'Could not read the text file.',
      );
    }
    if (isCancelled?.call() ?? false) {
      return ExtractionResult(itemCount: 0);
    }

    final text = _stripBom(content);
    if ((_isMarkdownName(path) || _looksLikeMarkdown(text))) {
      writer.writeRaw(text);
      return ExtractionResult(itemCount: 1);
    }

    final paragraphs = text
        .split(RegExp(r'\r?\n\s*\r?\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    for (var i = 0; i < paragraphs.length; i++) {
      if (isCancelled?.call() ?? false) break;
      writer.writeBlock(Block(
        type: BlockType.paragraph,
        lines: [paragraphs[i]],
      ));
      onProgress?.call(i + 1, paragraphs.length);
    }
    return ExtractionResult(itemCount: paragraphs.length);
  }

  String? _readContent(Uint8List? bytes, String? path) {
    if (bytes != null) {
      return _decode(bytes);
    }
    if (path != null) {
      final file = File(path);
      if (!file.existsSync()) return null;
      return _decode(file.readAsBytesSync());
    }
    return null;
  }

  /// UTF-8 bila valid; fallback latin1 (tidak pernah gagal).
  String _decode(Uint8List raw) {
    try {
      return utf8.decode(raw);
    } on FormatException {
      return latin1.decode(raw);
    }
  }

  String _stripBom(String s) {
    if (s.startsWith('\uFEFF')) return s.substring(1);
    return s;
  }

  bool _isMarkdownName(String? path) {
    if (path == null) return false;
    final lower = path.toLowerCase();
    return lower.endsWith('.md') || lower.endsWith('.markdown');
  }

  /// File `.md` yang valid (mengandung sintaks markdown) → passthrough.
  /// File `.txt` atau teks biasa → paragraf.
  bool _looksLikeMarkdown(String text) {
    if (text.trim().isEmpty) return false;
    final lines = text.split('\n');
    return lines.any((l) =>
        RegExp(r'^#{1,6} ').hasMatch(l) ||
        RegExp(r'^[-*+] ').hasMatch(l) ||
        RegExp(r'^\d+\. ').hasMatch(l) ||
        l.startsWith('> ') ||
        l.startsWith('```') ||
        RegExp(r'^\|.*\|$').hasMatch(l));
  }
}
