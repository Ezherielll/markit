import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_writer.dart';

/// Ekstraktor XML → indented ` ```xml ` code block.
///
/// Validasi via [XmlDocument.parse]; input malformed → corrupt.
class XmlExtractor implements FormatExtractor {
  const XmlExtractor();

  @override
  InputFormat get format => InputFormat.xml;

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
      throw ConvertException(ConvertError.corrupt, 'Could not read the XML file.');
    }
    if (isCancelled?.call() ?? false) {
      return ExtractionResult(itemCount: 0);
    }

    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ConvertException(ConvertError.noText, 'The XML file is empty.');
    }

    try {
      final doc = XmlDocument.parse(trimmed);
      final sb = StringBuffer()
        ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
        ..writeln(_pretty(doc.rootElement, 0));
      writer.writeRaw('```xml\n${sb.toString().trimRight()}\n```');
    } on XmlException catch (e) {
      throw ConvertException(ConvertError.corrupt, 'Invalid XML: ${e.message}');
    }

    onProgress?.call(1, 1);
    return ExtractionResult(itemCount: 1);
  }

  String _pretty(XmlElement node, int depth) {
    final indent = '  ' * depth;
    final sb = StringBuffer();
    final name = node.name.local;
    if (node.children.isEmpty && node.attributes.isEmpty) {
      // Leaf kosong.
      sb.writeln('$indent<$name/>');
      return sb.toString();
    }

    final attrs = node.attributes
        .map((a) => ' ${a.name.local}="${a.value}"')
        .join();
    final hasText = node.children.any((c) => c is XmlText && c.value.trim().isNotEmpty);

    if (hasText) {
      final text = node.children
          .whereType<XmlText>()
          .map((t) => t.value.trim())
          .join(' ')
          .trim();
      sb.writeln('$indent<$name$attrs>$text</$name>');
      return sb.toString();
    }

    sb.writeln('$indent<$name$attrs>');
    for (final child in node.children.whereType<XmlElement>()) {
      sb.write(_pretty(child, depth + 1));
    }
    sb.writeln('$indent</$name>');
    return sb.toString();
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
