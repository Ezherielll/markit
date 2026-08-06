import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_writer.dart';

/// Ekstraktor JSON → pretty-printed ` ```json ` code block.
///
/// Validasi parse; input invalid → [ConvertException.corrupt] (per-file
/// gagal, batch tetap lanjut — plan §5.3).
class JsonExtractor implements FormatExtractor {
  const JsonExtractor();

  @override
  InputFormat get format => InputFormat.json;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final text = _readText(bytes, path);
    if (text == null) {
      throw ConvertException(ConvertError.corrupt, 'Could not read the JSON file.');
    }
    if (isCancelled?.call() ?? false) {
      return ExtractionResult(itemCount: 0);
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ConvertException(ConvertError.noText, 'The JSON file is empty.');
    }

    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      throw ConvertException(
        ConvertError.corrupt,
        'Invalid JSON: ${e.message}',
      );
    }

    final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
    writer.writeRaw('```json\n$pretty\n```');
    onProgress?.call(1, 1);
    return ExtractionResult(itemCount: 1);
  }

  String? _readText(Uint8List? bytes, String? path) {
    if (bytes != null) {
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return latin1.decode(bytes);
      }
    }
    if (path != null && File(path).existsSync()) {
      return File(path).readAsStringSync();
    }
    return null;
  }
}
