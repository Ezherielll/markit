import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_writer.dart';
import '../../models/layout.dart';

/// Satu unit output: blok semantik (writeBlock) atau teks mentah (writeRaw).
sealed class _Out {
  const _Out();
}

class _OutBlock extends _Out {
  const _OutBlock(this.block);
  final Block block;
}

class _OutRaw extends _Out {
  const _OutRaw(this.raw);
  final String raw;
}

/// Ekstraktor HTML → blok markdown (plan §5.3):
/// - `h1–h6` → heading; `p` → paragraph; `ul/ol/li` → list;
/// - `table` → tabel markdown; `blockquote` → quote; `pre/code` → code block;
/// - `a` → teks + URL.
/// Tanpa struktur → satu blok teks (fallback).
class HtmlExtractor implements FormatExtractor {
  const HtmlExtractor();

  @override
  InputFormat get format => InputFormat.html;

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
      throw ConvertException(
        ConvertError.corrupt,
        'Could not read the HTML file.',
      );
    }
    if (isCancelled?.call() ?? false) {
      return ExtractionResult(itemCount: 0);
    }

    final document = html_parser.parse(text);
    final body = document.body;
    if (body == null) {
      throw ConvertException(
        ConvertError.noText,
        'The HTML document has no body.',
      );
    }

    final outs = _walk(body);
    if (outs.isEmpty) {
      final plain = _extractText(body);
      if (plain.trim().isEmpty) {
        throw ConvertException(
          ConvertError.noText,
          'No text could be extracted from the HTML document.',
        );
      }
      writer.writeBlock(Block(
        type: BlockType.paragraph,
        lines: [plain.trim()],
      ));
      return ExtractionResult(itemCount: 1);
    }

    var done = 0;
    for (final out in outs) {
      if (isCancelled?.call() ?? false) break;
      switch (out) {
        case _OutBlock(:final block):
          writer.writeBlock(block);
        case _OutRaw(:final raw):
          writer.writeRaw(raw);
      }
      done++;
      onProgress?.call(done, outs.length);
    }
    return ExtractionResult(itemCount: done);
  }

  /// Traversal DFS berurutan dokumen. Elemen kontainer (div/section/…)
  /// dilewati strukturnya — hanya kontennya yang dikunjungi.
  List<_Out> _walk(dom.Element el) {
    final outs = <_Out>[];
    for (final child in el.children) {
      outs.addAll(_visit(child));
    }
    return outs;
  }

  List<_Out> _visit(dom.Element el) {
    final tag = el.localName ?? '';
    switch (tag) {
      case 'h1':
      case 'h2':
      case 'h3':
      case 'h4':
      case 'h5':
      case 'h6':
        return [
          _OutBlock(Block(
            type: BlockType.heading,
            headingLevel: int.parse(tag.substring(1)),
            lines: [_inlineText(el)],
          )),
        ];
      case 'p':
        return [
          _OutBlock(Block(type: BlockType.paragraph, lines: [_inlineText(el)])),
        ];
      case 'ul':
      case 'ol':
        return [
          for (final li in el.children.where((c) => c.localName == 'li'))
            _OutBlock(
              Block(type: BlockType.listItem, lines: [_inlineText(li)]),
            ),
        ];
      case 'table':
        return [_OutRaw(_tableMarkdown(el))];
      case 'blockquote':
        return [_OutRaw('> ${_inlineText(el)}')];
      case 'pre':
      case 'code':
        return [_OutRaw('```\n${_codeText(el)}\n```')];
      case 'div':
      case 'section':
      case 'article':
      case 'main':
      case 'header':
      case 'footer':
      case 'nav':
      case 'body':
      case 'aside':
        return _walk(el);
      default:
        final own = _ownText(el);
        if (own.trim().isEmpty) return const [];
        return [
          _OutBlock(Block(type: BlockType.paragraph, lines: [own.trim()])),
        ];
    }
  }

  /// Teks inline: teks langsung + link (teks + URL), tanpa konten child blok.
  String _inlineText(dom.Element el) {
    final sb = StringBuffer();
    for (final node in el.nodes) {
      if (node is dom.Text) {
        sb.write(node.text);
      } else if (node is dom.Element) {
        final tag = node.localName;
        if (tag == 'a') {
          final href = node.attributes['href'];
          final label = _inlineText(node);
          if (href != null && href.isNotEmpty && label.trim().isNotEmpty) {
            sb.write('$label ($href)');
          } else {
            sb.write(label);
          }
        } else if (tag == 'br') {
          sb.write(' ');
        } else if (tag == 'strong' || tag == 'b') {
          sb.write('**${_inlineText(node)}**');
        } else if (tag == 'em' || tag == 'i') {
          sb.write('_${_inlineText(node)}_');
        } else if (tag == 'code') {
          sb.write('`${_inlineText(node)}`');
        } else {
          sb.write(_inlineText(node));
        }
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Teks yang "dimiliki" elemen langsung — bukan anak block elemen.
  String _ownText(dom.Element el) {
    final sb = StringBuffer();
    for (final node in el.nodes) {
      if (node is dom.Text) {
        sb.write(node.text);
      } else if (node is dom.Element &&
          !const [
            'p',
            'div',
            'section',
            'ul',
            'ol',
            'table',
            'pre',
            'blockquote',
          ].contains(node.localName)) {
        sb.write(_ownText(node));
      }
    }
    return sb.toString();
  }

  String _codeText(dom.Element el) {
    final sb = StringBuffer();
    for (final node in el.nodes) {
      if (node is dom.Text) {
        sb.write(node.text);
      } else if (node is dom.Element) {
        sb.write(_codeText(node));
      }
    }
    return sb.toString().trim();
  }

  String _tableMarkdown(dom.Element table) {
    final sb = StringBuffer();
    var first = true;
    for (final tr in table.querySelectorAll('tr')) {
      final cells = tr
          .querySelectorAll('th, td')
          .map((c) => _inlineText(c).replaceAll('|', r'\|'))
          .toList();
      if (cells.isEmpty) continue;
      sb.writeln('| ${cells.join(' | ')} |');
      if (first) {
        sb.writeln('| ${cells.map((_) => '---').join(' | ')} |');
        first = false;
      }
    }
    return sb.toString().trimRight();
  }

  /// Fallback: seluruh teks tanpa struktur.
  String _extractText(dom.Element root) {
    final sb = StringBuffer();
    for (final node in root.nodes) {
      if (node is dom.Text) {
        sb.write(node.text);
      } else if (node is dom.Element) {
        sb.write(_extractText(node));
        sb.write(' ');
      }
    }
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
