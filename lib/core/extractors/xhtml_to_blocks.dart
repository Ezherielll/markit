import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../models/layout.dart';
import '../markdown_table.dart';

/// XHTML fragment → markdown blocks (headings, paragraphs, nested lists,
/// tables, links as `text (url)`, bold/italic emphasis).
List<Block> xhtmlToBlocks(String xhtml) {
  final doc = html_parser.parse(xhtml);
  final blocks = <Block>[];
  _walkChildren(doc.body ?? doc.documentElement!, blocks, 0);
  return blocks;
}

void _walkChildren(Element parent, List<Block> blocks, int listDepth) {
  for (final node in parent.nodes) {
    if (node is! Element) continue;
    switch (node.localName) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        _heading(node, blocks);
      case 'p':
        _paragraph(node, blocks);
      case 'ul':
      case 'ol':
        _walkChildren(node, blocks, listDepth + 1);
      case 'li':
        _listItem(node, blocks, listDepth);
      case 'table':
        _table(node, blocks);
      case 'blockquote':
        _walkChildren(node, blocks, listDepth);
      case 'script':
      case 'style':
      case 'head':
        break; // skipped
      default:
        _walkChildren(node, blocks, listDepth);
    }
  }
}

/// h1-h6 → heading block with the level parsed from the tag name.
void _heading(Element node, List<Block> blocks) {
  final text = _inline(node);
  if (text.isEmpty) return;
  blocks.add(Block(
    type: BlockType.heading,
    headingLevel: int.parse(node.localName!.substring(1)),
    lines: [text],
  ));
}

void _paragraph(Element node, List<Block> blocks) {
  final text = _inline(node);
  if (text.isEmpty) return;
  blocks.add(Block(type: BlockType.paragraph, lines: [text]));
}

/// li → list item at [listDepth] - 1; nested ul/ol are walked at
/// [listDepth] so their items land one level deeper.
void _listItem(Element node, List<Block> blocks, int listDepth) {
  final text = _inline(node);
  if (text.isEmpty) return;
  blocks.add(Block(
    type: BlockType.unorderedListItem,
    lines: [text],
    listDepth: listDepth - 1,
  ));
  _walkChildren(node, blocks, listDepth);
}

void _table(Element node, List<Block> blocks) {
  final rows = _tableRows(node);
  if (rows.isEmpty) return;
  blocks.add(Block(
    type: BlockType.paragraph,
    lines: [tableToMarkdown(rows)],
  ));
}

String _inline(Element parent) {
  final sb = StringBuffer();
  for (final node in parent.nodes) {
    if (node is Text) {
      sb.write(node.text);
    } else if (node is Element) {
      switch (node.localName) {
        case 'br':
          sb.write(' ');
        case 'strong':
        case 'b':
          sb.write('**${_inline(node)}**');
        case 'em':
        case 'i':
          sb.write('*${_inline(node)}*');
        case 'a':
          final href = node.attributes['href'];
          final text = _inline(node);
          sb.write(href == null ? text : '$text ($href)');
        case 'script':
        case 'style':
        case 'ul':
        case 'ol':
          break;
        default:
          sb.write(_inline(node));
      }
    }
  }
  return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

List<List<String>> _tableRows(Element table) {
  final rows = <List<String>>[];
  for (final tr in table.querySelectorAll('tr')) {
    final cells = <String>[];
    for (final cell in tr.children) {
      if (cell.localName == 'td' || cell.localName == 'th') {
        cells.add(_inline(cell));
      }
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  return rows;
}
