import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/layout.dart';
import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_writer.dart';

/// Word (Office Open XML: `.docx`/`.docm`) extractor → markdown.
///
/// Architecture: DOCX is a ZIP containing XML. Reads:
/// - `word/document.xml` — main content (w:p paragraphs, w:tbl tables);
/// - `word/styles.xml` — map styleId → name (heading 1..6);
/// - `word/numbering.xml` — numFmt "decimal" → ordered list.
/// Pure Dart, no FFI — runs on desktop (isolate) & web (inline).
///
/// Contract: corrupt file (not zip / missing document.xml) → ConvertException
/// corrupt; no text → noText; cancellation checked per block.
class DocxExtractor implements FormatExtractor {
  const DocxExtractor();

  @override
  InputFormat get format => InputFormat.word;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final raw = await _readBytes(bytes, path);
    if (raw == null) {
      throw ConvertException(
        ConvertError.corrupt,
        'Could not read the DOCX file.',
      );
    }

    final archive = _openZip(raw);
    final documentXml = _entryText(archive, 'word/document.xml');
    if (documentXml == null) {
      throw ConvertException(
        ConvertError.corrupt,
        'The DOCX file has no word/document.xml.',
      );
    }

    final styles = _parseStyles(_entryText(archive, 'word/styles.xml'));
    final orderedNumIds = _parseNumbering(
      _entryText(archive, 'word/numbering.xml'),
    );

    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(documentXml);
    } on XmlException catch (e) {
      throw ConvertException(
        ConvertError.corrupt,
        'The DOCX document.xml is not valid XML: ${e.message}',
      );
    }

    final body = doc.rootElement.children
        .where((n) => n is XmlElement && n.name.local == 'body')
        .cast<XmlElement>()
        .firstOrNull;
    if (body == null) {
      throw ConvertException(
        ConvertError.corrupt,
        'The DOCX document has no body.',
      );
    }

    final blocks = <Block>[];
    final raws = <String>[];
    _walkBody(body, blocks, raws, styles, orderedNumIds);

    if (blocks.isEmpty && raws.isEmpty) {
      throw ConvertException(
        ConvertError.noText,
        'No text could be extracted from the DOCX document.',
      );
    }

    return _emit(blocks, raws, writer, onProgress, isCancelled);
  }

  /// Walk `<w:body>` children: paragraph → Block, table → raw markdown.
  ///
  /// [orderedCounter] tracks consecutive ordered list blocks (1-based);
  /// resets when leaving ordered sequence (other paragraph / table).
  void _walkBody(
    XmlElement body,
    List<Block> blocks,
    List<String> raws,
    Map<String, int> styles,
    Map<String, bool> orderedNumIds,
  ) {
    var orderedCounter = 0;
    for (final node in body.children) {
      if (node is! XmlElement) continue;
      switch (node.name.local) {
        case 'p':
          final block = _paragraphToBlock(node, styles, orderedNumIds);
          if (block == null) continue;
          if (block.type == BlockType.orderedListItem) {
            orderedCounter++;
            blocks.add(Block(
              type: BlockType.orderedListItem,
              lines: block.lines,
              listIndex: orderedCounter,
            ));
          } else {
            orderedCounter = 0;
            blocks.add(block);
          }
        case 'tbl':
          raws.add(_tableMarkdown(node));
          orderedCounter = 0;
        case 'sectPr':
          break;
      }
    }
  }

  /// Write blocks + raws to writer; cancel mid-way via [isCancelled].
  ExtractionResult _emit(
    List<Block> blocks,
    List<String> raws,
    MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  ) {
    var done = 0;
    for (final block in blocks) {
      if (isCancelled?.call() ?? false) break;
      writer.writeBlock(block);
      done++;
      onProgress?.call(done, blocks.length + raws.length);
    }
    for (final raw in raws) {
      if (isCancelled?.call() ?? false) break;
      writer.writeRaw(raw);
      done++;
      onProgress?.call(done, blocks.length + raws.length);
    }
    return ExtractionResult(itemCount: done);
  }

  Future<Uint8List?> _readBytes(Uint8List? bytes, String? path) async {
    if (bytes != null && bytes.isNotEmpty) return bytes;
    if (path != null) {
      try {
        return await File(path).readAsBytes();
      } on FileSystemException {
        return null;
      }
    }
    return null;
  }

  Archive _openZip(Uint8List raw) {
    try {
      return ZipDecoder().decodeBytes(raw);
    } on ArchiveException {
      throw ConvertException(
        ConvertError.corrupt,
        'The DOCX file is not a valid ZIP archive.',
      );
    }
  }

  String? _entryText(Archive archive, String name) {
    final entry = archive.files.where((f) => f.name == name).firstOrNull;
    if (entry == null) return null;
    return utf8.decode(entry.content as List<int>, allowMalformed: true);
  }

  /// Map styleId → heading level (1..6) from style name ("heading 1" etc).
  Map<String, int> _parseStyles(String? stylesXml) {
    final result = <String, int>{};
    if (stylesXml == null) return result;
    try {
      final doc = XmlDocument.parse(stylesXml);
      for (final style in doc.rootElement.descendants.whereType<XmlElement>()) {
        if (style.name.local != 'style') continue;
        final id = style.getAttribute('w:styleId') ??
            style.getAttribute('styleId');
        final name = style.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'name')
            .firstOrNull
            ?.getAttribute('w:val');
        if (id == null || name == null) continue;
        final m = RegExp(r'heading\s*([1-6])', caseSensitive: false)
            .firstMatch(name);
        if (m != null) result[id] = int.parse(m.group(1)!);
      }
    } on XmlException {
      // corrupt styles.xml → all paragraphs treated as body (non-fatal).
    }
    return result;
  }

  /// Map numId → true if format is decimal (ordered), false = bullet.
  Map<String, bool> _parseNumbering(String? numberingXml) {
    final result = <String, bool>{};
    if (numberingXml == null) return result;
    try {
      final doc = XmlDocument.parse(numberingXml);
      final abstractNumFmt = _parseAbstractNumFormats(doc);
      for (final node in doc.rootElement.descendants.whereType<XmlElement>()) {
        if (node.name.local != 'num') continue;
        final numId = node.getAttribute('w:numId') ??
            node.getAttribute('numId');
        final absId = node.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'abstractNumId')
            .firstOrNull
            ?.getAttribute('w:val');
        if (numId != null && absId != null) {
          result[numId] = abstractNumFmt[absId] ?? false;
        }
      }
    } on XmlException {
      // corrupt numbering.xml → all numPr treated as bullet (non-fatal).
    }
    return result;
  }

  /// Map abstractNumId → true if numFmt is numbered (decimal/letter/roman).
  Map<String, bool> _parseAbstractNumFormats(XmlDocument doc) {
    final result = <String, bool>{};
    for (final node in doc.rootElement.descendants.whereType<XmlElement>()) {
      if (node.name.local != 'abstractNum') continue;
      final id = node.getAttribute('w:abstractNumId') ??
          node.getAttribute('abstractNumId');
      final fmt = node.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 'numFmt')
          .firstOrNull
          ?.getAttribute('w:val');
      if (id != null) {
        result[id] = (fmt ?? '') == 'decimal' ||
            (fmt ?? '') == 'lowerLetter' ||
            (fmt ?? '') == 'lowerRoman';
      }
    }
    return result;
  }

  /// Convert single `<w:p>` → Block; null if empty paragraph (pPr only).
  Block? _paragraphToBlock(
    XmlElement p,
    Map<String, int> styles,
    Map<String, bool> orderedNumIds,
  ) {
    final pPr = p.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'pPr')
        .firstOrNull;

    // Heading from paragraph style.
    final styleId = pPr?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'pStyle')
        .firstOrNull
        ?.getAttribute('w:val');
    final headingLevel = styleId == null ? null : styles[styleId];
    if (headingLevel != null) {
      final text = _paragraphText(p);
      if (text.isEmpty) return null;
      return Block(
        type: BlockType.heading,
        headingLevel: headingLevel,
        lines: [text],
      );
    }

    // List via numPr.
    final numId = pPr?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'numPr')
        .firstOrNull
        ?.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'numId')
        .firstOrNull
        ?.getAttribute('w:val');
    if (numId != null) {
      final text = _paragraphText(p);
      if (text.isEmpty) return null;
      return Block(
        type: orderedNumIds[numId] == true
            ? BlockType.orderedListItem
            : BlockType.unorderedListItem,
        lines: [text],
      );
    }

    final text = _paragraphText(p);
    if (text.isEmpty) return null;
    return Block(type: BlockType.paragraph, lines: [text]);
  }

  /// Join paragraph text: w:t (xml:space preserve), w:tab, w:br, hyperlink.
  String _paragraphText(XmlElement p) {
    final sb = StringBuffer();
    for (final node in p.descendants.whereType<XmlElement>()) {
      switch (node.name.local) {
        case 't':
          sb.write(node.innerText);
        case 'tab':
          sb.write(' ');
        case 'br':
          final type = node.getAttribute('w:type');
          if (type != 'page') sb.write(' ');
        case 'cr':
          sb.write(' ');
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// `<w:tbl>` → markdown table (same pattern as HtmlExtractor._tableMarkdown).
  String _tableMarkdown(XmlElement tbl) {
    final sb = StringBuffer();
    var first = true;
    for (final tr in tbl.descendants.whereType<XmlElement>()) {
      if (tr.name.local != 'tr') continue;
      final cells = _rowCells(tr);
      if (cells.isEmpty) continue;
      sb.writeln('| ${cells.join(' | ')} |');
      if (first) {
        sb.writeln('| ${cells.map((_) => '---').join(' | ')} |');
        first = false;
      }
    }
    return sb.toString().trimRight();
  }

  /// Table row cells: `<w:tc>` (paragraphs inside cell) or `<w:p>`
  /// directly as cell (concise format); `|` escaped for markdown.
  List<String> _rowCells(XmlElement tr) {
    final cells = <String>[];
    for (final child in tr.children.whereType<XmlElement>()) {
      switch (child.name.local) {
        case 'tc':
          final cellText = child.descendants
              .whereType<XmlElement>()
              .where((e) => e.name.local == 'p')
              .map(_paragraphText)
              .where((t) => t.isNotEmpty)
              .join(' ');
          cells.add(cellText.replaceAll('|', r'\|'));
        case 'p':
          cells.add(_paragraphText(child).replaceAll('|', r'\|'));
      }
    }
    return cells;
  }
}
