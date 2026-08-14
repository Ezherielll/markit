import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/layout.dart';
import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_table.dart';
import '../output.dart';
import 'input_bytes.dart';

/// OpenDocument extractor — one parser for .odt / .ods / .odp (all three
/// share `content.xml`). Headings, paragraphs, nested lists, and tables.
///
/// Scope (v1): text documents, spreadsheets, and presentations. Notes,
/// tracked changes, and image content are skipped; `draw:text-box` text IS
/// included. Style-based formatting is flattened.
class OdfExtractor implements FormatExtractor {
  const OdfExtractor();

  @override
  InputFormat get format => InputFormat.opendocument;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required OutputTarget output,
    void Function(int done, int total, int phase, int elapsedMs)? onProgress,
    bool Function()? isCancelled,
  }) {
    return withMarkdownWriter(output, run: (writer) async {
      final raw = await readInputBytes(bytes, path);
      if (raw == null) {
        throw ConvertException(ConvertError.corrupt, 'Could not read the OpenDocument file.');
      }
      final contentXml = _entryText(raw, 'content.xml');
      if (contentXml == null) {
        throw ConvertException(ConvertError.corrupt, 'The OpenDocument file has no content.xml.');
      }

      final XmlDocument doc;
      try {
        doc = XmlDocument.parse(contentXml);
      } on XmlException catch (e) {
        throw ConvertException(ConvertError.corrupt, 'The OpenDocument content.xml is not valid XML: ${e.message}');
      }

      final body = doc.rootElement.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'body')
          .firstOrNull;
      if (body == null) {
        throw ConvertException(ConvertError.corrupt, 'The OpenDocument file has no body.');
      }

      final blocks = <Block>[];
      _walk(body, blocks, 0);
      if (blocks.isEmpty) {
        throw ConvertException(ConvertError.noText, 'No text could be extracted from the OpenDocument file.');
      }

      var done = 0;
      for (final b in blocks) {
        if (isCancelled?.call() ?? false) break;
        writer.writeBlock(b);
        done++;
        onProgress?.call(done, blocks.length, 1, 0);
      }
      return ExtractionResult(itemCount: done);
    });
  }

  /// Walk body children into blocks. [listDepth] tracks nested text:list.
  void _walk(XmlElement parent, List<Block> blocks, int listDepth) {
    for (final node in parent.children) {
      if (node is! XmlElement) continue;
      switch (node.name.local) {
        case 'h':
          _heading(node, blocks);
        case 'p':
          _paragraph(node, blocks, listDepth);
        case 'list':
          _walk(node, blocks, listDepth + 1);
        case 'list-item':
          _walk(node, blocks, listDepth);
        case 'table':
          _walkTable(node, blocks);
        case 'page':
          _page(node, blocks, listDepth);
        case 'annotation':
        case 'tracked-changes':
        case 'note':
        case 'change-track-change':
          break; // skipped: notes / change tracking
        default:
          _walk(node, blocks, listDepth);
      }
    }
  }

  /// text:h → heading (attr text:outline-level 1..6, default 1).
  void _heading(XmlElement node, List<Block> blocks) {
    final level = int.tryParse(node.getAttribute('outline-level', namespace: '*') ?? '') ?? 1;
    final text = _inlineText(node);
    if (text.isNotEmpty) {
      blocks.add(Block(
        type: BlockType.heading,
        headingLevel: level.clamp(1, 6),
        lines: [text],
      ));
    }
  }

  /// text:p → paragraph, or list item when inside a text:list.
  void _paragraph(XmlElement node, List<Block> blocks, int listDepth) {
    final text = _inlineText(node);
    if (text.isNotEmpty) {
      blocks.add(listDepth > 0
          ? Block(type: BlockType.unorderedListItem, lines: [text], listDepth: listDepth - 1)
          : Block(type: BlockType.paragraph, lines: [text]));
    }
  }

  /// draw:page → `# {name}` heading, then its text children.
  void _page(XmlElement node, List<Block> blocks, int listDepth) {
    final name = node.getAttribute('name', namespace: '*');
    if (name != null && name.isNotEmpty) {
      blocks.add(Block(type: BlockType.heading, headingLevel: 1, lines: ['# $name']));
    }
    _walk(node, blocks, listDepth);
  }

  /// Flatten inline content (text:span, text:tab, text:s, text:line-break,
  /// draw:text-box) into a single string.
  String _inlineText(XmlElement parent) {
    final sb = StringBuffer();
    _inline(parent, sb);
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  void _inline(XmlElement parent, StringBuffer sb) {
    for (final node in parent.children) {
      if (node is XmlText) {
        sb.write(node.value);
      } else if (node is XmlElement) {
        switch (node.name.local) {
          case 'tab':
          case 'line-break':
            sb.write(' ');
          case 's':
            final count = int.tryParse(node.getAttribute('c', namespace: '*') ?? '') ?? 1;
            sb.write(' ' * count.clamp(1, 20));
          case 'span':
          case 'text-box':
          case 'frame':
            _inline(node, sb);
          case 'annotation':
          case 'note':
            break;
          default:
            _inline(node, sb);
        }
      }
    }
  }

  /// table:table → markdown table (cells = joined text:p texts).
  void _walkTable(XmlElement table, List<Block> blocks) {
    final rows = <List<String>>[];
    for (final row in table.descendants.whereType<XmlElement>()) {
      if (row.name.local != 'table-row') continue;
      final cells = <String>[];
      for (final cell in row.children.whereType<XmlElement>()) {
        if (cell.name.local != 'table-cell') continue;
        final texts = cell.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'p')
            .map(_inlineText)
            .where((t) => t.isNotEmpty)
            .toList();
        cells.add(texts.join(' '));
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.isNotEmpty) {
      final name = table.getAttribute('name', namespace: '*');
      if (name != null && name.isNotEmpty) {
        blocks.add(Block(type: BlockType.heading, headingLevel: 1, lines: ['# $name']));
      }
      blocks.add(Block(type: BlockType.paragraph, lines: [tableToMarkdown(rows)]));
    }
  }

  String? _entryText(Uint8List raw, String name) {
    try {
      final archive = ZipDecoder().decodeBytes(raw);
      final entry = archive.files.where((f) => f.isFile && f.name == name).firstOrNull;
      if (entry == null) return null;
      return utf8.decode(entry.content as List<int>, allowMalformed: true);
    } on ArchiveException {
      throw ConvertException(ConvertError.corrupt, 'The OpenDocument file is not a valid ZIP archive.');
    }
  }
}
