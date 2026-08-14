import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/layout.dart';
import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_table.dart';
import '../markdown_writer.dart';
import '../output.dart';
import 'input_bytes.dart';

/// PowerPoint extractor (.pptx/.pptm/.ppsx/.ppsm) → markdown.
///
/// Per slide: title placeholder → heading level 1; body paragraphs → list
/// items (a:buChar/a:buAutoNum) or paragraphs; a:tbl → markdown table.
/// Slides are separated by a blank line. Emphasis (a:rPr b/i) is kept.
class PptxExtractor implements FormatExtractor {
  const PptxExtractor();

  @override
  InputFormat get format => InputFormat.powerpoint;

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
        throw ConvertException(
          ConvertError.corrupt,
          'Could not read the PowerPoint file.',
        );
      }
      final archive = _openZip(raw);
      final slides = _slideEntries(archive);
      if (slides.isEmpty) {
        throw ConvertException(
          ConvertError.corrupt,
          'The PowerPoint file has no slides.',
        );
      }

      final blocks = _collectBlocks(slides);
      if (!_hasText(blocks)) {
        throw ConvertException(
          ConvertError.noText,
          'No text could be extracted from the PowerPoint file.',
        );
      }
      return _emit(blocks, writer, onProgress, isCancelled);
    });
  }

  /// Parse each slide (in numeric order) into blocks; slides are separated
  /// by a blank line.
  List<Block> _collectBlocks(List<ArchiveFile> slides) {
    final blocks = <Block>[];
    for (final entry in slides) {
      final doc = _parseXml(entry, 'slide');
      final body = _firstLocal(doc.rootElement, 'body') ?? doc.rootElement;
      if (blocks.isNotEmpty) {
        blocks.add(Block(type: BlockType.paragraph, lines: ['']));
      }
      _walkSlide(body, blocks);
    }
    return blocks;
  }

  /// Write blocks to the writer; cancel mid-way via [isCancelled].
  ExtractionResult _emit(
    List<Block> blocks,
    MarkdownWriter writer,
    void Function(int done, int total, int phase, int elapsedMs)? onProgress,
    bool Function()? isCancelled,
  ) {
    var done = 0;
    for (final b in blocks) {
      if (isCancelled?.call() ?? false) break;
      writer.writeBlock(b);
      done++;
      onProgress?.call(done, blocks.length, 1, 0);
    }
    return ExtractionResult(itemCount: done);
  }

  bool _hasText(List<Block> blocks) =>
      blocks.any((b) => b.text.trim().isNotEmpty);

  /// `ppt/slides/slideN.xml` entries, sorted numerically by N.
  List<ArchiveFile> _slideEntries(Archive archive) {
    final re = RegExp(r'^ppt/slides/slide(\d+)\.xml$');
    final slides = <(int, ArchiveFile)>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final m = re.firstMatch(f.name);
      if (m == null) continue;
      slides.add((int.parse(m.group(1)!), f));
    }
    slides.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final s in slides) s.$2];
  }

  /// Walk a slide: shapes → headings/paragraphs/list items; graphicFrame
  /// → tables. Unknown containers (cSld, spTree, grpSp) are recursed into.
  void _walkSlide(XmlElement parent, List<Block> blocks) {
    for (final node in parent.children) {
      if (node is! XmlElement) continue;
      switch (node.name.local) {
        case 'sp':
          _shape(node, blocks);
        case 'graphicFrame':
          _graphicFrame(node, blocks);
        default:
          _walkSlide(node, blocks);
      }
    }
  }

  /// p:sp → title placeholder (ph type="title") becomes a level-1 heading;
  /// otherwise its a:p paragraphs become list items or paragraphs.
  void _shape(XmlElement sp, List<Block> blocks) {
    final txBody = _firstLocal(sp, 'txBody');
    if (txBody == null) return;
    if (_isTitle(sp)) {
      _titleHeading(txBody, blocks);
    } else {
      _bodyParagraphs(txBody, blocks);
    }
  }

  /// First non-empty paragraph of a title shape → heading level 1.
  void _titleHeading(XmlElement txBody, List<Block> blocks) {
    for (final p in txBody.children.whereType<XmlElement>()) {
      if (p.name.local != 'p') continue;
      final text = _paraText(p);
      if (text.isEmpty) continue;
      blocks.add(Block(type: BlockType.heading, headingLevel: 1, lines: [text]));
      return;
    }
  }

  /// Body paragraphs: a:buChar/a:buAutoNum → bullet item, else paragraph.
  void _bodyParagraphs(XmlElement txBody, List<Block> blocks) {
    for (final p in txBody.children.whereType<XmlElement>()) {
      if (p.name.local != 'p') continue;
      final text = _paraText(p);
      if (text.isEmpty) continue;
      blocks.add(_isBullet(p)
          ? Block(type: BlockType.unorderedListItem, lines: [text])
          : Block(type: BlockType.paragraph, lines: [text]));
    }
  }

  /// True when the shape's nvPr carries a placeholder of type "title".
  bool _isTitle(XmlElement sp) {
    final nvPr = _firstLocal(sp, 'nvPr');
    final ph = nvPr == null ? null : _firstLocal(nvPr, 'ph');
    return ph?.getAttribute('type', namespace: '*') == 'title';
  }

  /// True when a:p has a bullet marker (a:buChar or a:buAutoNum).
  bool _isBullet(XmlElement p) {
    final pPr = p.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'pPr')
        .firstOrNull;
    if (pPr == null) return false;
    return pPr.children
        .whereType<XmlElement>()
        .any((e) => e.name.local == 'buChar' || e.name.local == 'buAutoNum');
  }

  /// p:graphicFrame → a:tbl → markdown table block.
  void _graphicFrame(XmlElement frame, List<Block> blocks) {
    final tbl = _firstLocal(frame, 'tbl');
    if (tbl == null) return;
    final rows = _tableRows(tbl);
    if (rows.isEmpty) return;
    blocks.add(Block(type: BlockType.paragraph, lines: [tableToMarkdown(rows)]));
  }

  /// a:tbl → rows; each a:tc cell joins the text of its a:p paragraphs.
  List<List<String>> _tableRows(XmlElement tbl) {
    final rows = <List<String>>[];
    for (final tr in tbl.descendants.whereType<XmlElement>()) {
      if (tr.name.local != 'tr') continue;
      final cells = <String>[];
      for (final tc in tr.children.whereType<XmlElement>()) {
        if (tc.name.local != 'tc') continue;
        final cellText = tc.descendants
            .whereType<XmlElement>()
            .where((e) => e.name.local == 'p')
            .map(_paraText)
            .where((t) => t.isNotEmpty)
            .join(' ');
        cells.add(cellText);
      }
      if (cells.isNotEmpty) rows.add(cells);
    }
    return rows;
  }

  /// a:p → concatenated run text; a:br → ' '; whitespace collapsed.
  String _paraText(XmlElement p) {
    final sb = StringBuffer();
    for (final node in p.children) {
      if (node is XmlText) {
        sb.write(node.value);
      } else if (node is XmlElement) {
        switch (node.name.local) {
          case 'r':
            _run(node, sb);
          case 'br':
            sb.write(' ');
          default:
            break;
        }
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// a:r → its a:t text; a:rPr b="1"/i="1" → **bold** / *italic*.
  void _run(XmlElement r, StringBuffer sb) {
    final rPr = r.children
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'rPr')
        .firstOrNull;
    final bold = rPr?.getAttribute('b', namespace: '*') == '1';
    final italic = rPr?.getAttribute('i', namespace: '*') == '1';
    final text = _runText(r);
    if (text.isEmpty) return;
    sb.write(_emphasize(text, bold, italic));
  }

  String _runText(XmlElement r) {
    final sb = StringBuffer();
    for (final node in r.children) {
      if (node is XmlText) {
        sb.write(node.value);
      } else if (node is XmlElement) {
        switch (node.name.local) {
          case 't':
            sb.write(node.innerText);
          case 'br':
            sb.write(' ');
          default:
            break;
        }
      }
    }
    return sb.toString();
  }

  String _emphasize(String text, bool bold, bool italic) {
    if (bold && italic) return '***$text***';
    if (bold) return '**$text**';
    if (italic) return '*$text*';
    return text;
  }

  XmlDocument _parseXml(ArchiveFile entry, String label) {
    final xml = utf8.decode(entry.content as List<int>, allowMalformed: true);
    try {
      return XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw ConvertException(
        ConvertError.corrupt,
        'The PowerPoint $label is not valid XML: ${e.message}',
      );
    }
  }

  Archive _openZip(Uint8List raw) {
    try {
      return ZipDecoder().decodeBytes(raw);
    } on ArchiveException {
      throw ConvertException(
        ConvertError.corrupt,
        'The PowerPoint file is not a valid ZIP archive.',
      );
    }
  }

  XmlElement? _firstLocal(XmlElement root, String local) => root.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == local)
      .firstOrNull;
}
