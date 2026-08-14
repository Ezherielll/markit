import 'dart:convert';
import 'dart:typed_data';

import '../../models/layout.dart';
import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../output.dart';
import 'input_bytes.dart';

/// RTF extractor → markdown paragraphs with bold/italic emphasis.
///
/// Scope (v1): paragraphs (`\par`), emphasis (`\b`/`\i`), unicode/hex escapes,
/// bullets (`\bullet`), tabs. Destination groups (`\fonttbl`, `\colortbl`,
/// `\stylesheet`, `\info`, `\*...`) are skipped. RTF tables and style-based
/// headings are flattened to text (roadmap).
class RtfExtractor implements FormatExtractor {
  const RtfExtractor();

  @override
  InputFormat get format => InputFormat.rtf;

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
        throw ConvertException(ConvertError.corrupt, 'Could not read the RTF file.');
      }
      if (isCancelled?.call() ?? false) {
        return ExtractionResult(itemCount: 0);
      }
      final decoded = utf8.decode(raw, allowMalformed: true);
      if (!_hasRtfHeader(decoded)) {
        throw ConvertException(
          ConvertError.corrupt,
          'Not an RTF document: the {\\rtf header is missing.',
        );
      }
      final text = _parse(decoded);
      final blocks = _textToBlocks(text);
      if (blocks.isEmpty) {
        throw ConvertException(
          ConvertError.noText,
          'No text could be extracted from the RTF document.',
        );
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

  /// Split parsed text into blocks: lines starting with '- ' (written by
  /// `\bullet`) become list items — a plain paragraph would have the dash
  /// escaped by the writer; everything else is a plain paragraph.
  List<Block> _textToBlocks(String text) {
    return text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .map((l) {
      if (l.startsWith('- ')) {
        return Block(type: BlockType.unorderedListItem, lines: [l.substring(2)]);
      }
      return Block(type: BlockType.paragraph, lines: [l]);
    }).toList();
  }

  /// Parse RTF source → plain text with `\n` paragraph separators and inline
  /// markdown emphasis markers.
  String _parse(String src) {
    final sb = StringBuffer();
    var bold = false;
    var italic = false;
    // Emphasis state per group depth: pushed on '{' (content groups only),
    // popped on '}' so emphasis closes exactly where the group changes.
    final stateStack = <({bool bold, bool italic})>[];
    var i = 0;

    void toggleBold(bool on) {
      if (on == bold) return;
      bold = on;
      sb.write('**');
    }

    void toggleItalic(bool on) {
      if (on == italic) return;
      italic = on;
      sb.write('*');
    }

    while (i < src.length) {
      final c = src[i];
      if (c == '{') {
        i = _openGroup(src, i, stateStack, bold, italic);
        continue;
      }
      if (c == '}') {
        i = _closeEmphasis(i, toggleBold, toggleItalic, stateStack);
        continue;
      }
      if (c == '\\') {
        i = _parseEscapeOrWord(sb, src, i, toggleBold, toggleItalic);
        continue;
      }
      if (c == '\r' || c == '\n') {
        i++;
        continue;
      }
      sb.write(c);
      i++;
    }
    return sb.toString();
  }

  /// Handle a '{' at [i]: skip destination groups wholesale; a content group
  /// (not skipped) records the emphasis state at its opening so the matching
  /// '}' can restore exactly what changed. Returns the index after the group
  /// opening (or after the whole skipped group).
  int _openGroup(
    String src,
    int i,
    List<({bool bold, bool italic})> stateStack,
    bool bold,
    bool italic,
  ) {
    final end = _skipDestinationGroup(src, i);
    if (end == i + 1) {
      stateStack.add((bold: bold, italic: italic));
    }
    return end;
  }

  /// Close an emphasis group: restore the bold/italic state recorded when the
  /// group opened, emitting closing markers only for the emphasis that
  /// changed inside this group (inner groups close before outer ones).
  /// Returns the index after the '}'.
  int _closeEmphasis(
    int i,
    void Function(bool) toggleBold,
    void Function(bool) toggleItalic,
    List<({bool bold, bool italic})> stateStack,
  ) {
    final saved = stateStack.isEmpty
        ? (bold: false, italic: false)
        : stateStack.removeLast();
    toggleBold(saved.bold);
    toggleItalic(saved.italic);
    return i + 1;
  }

  /// Handle a '\' at [i]: hex escape, escaped literal, or control word;
  /// returns the index after the construct (or [src.length] when truncated).
  int _parseEscapeOrWord(
    StringBuffer sb,
    String src,
    int i,
    void Function(bool) toggleBold,
    void Function(bool) toggleItalic,
  ) {
    if (i + 1 >= src.length) return src.length;
    final next = src[i + 1];
    if (next == '\'') {
      return _writeHexEscape(sb, src, i);
    }
    if (_isEscapedLiteral(next)) {
      return _writeEscapedLiteral(sb, next, i);
    }
    return _writeControlWord(sb, src, i, toggleBold, toggleItalic);
  }

  /// Skip a destination group from the '{' at [i] ('{' + '\' + word,
  /// possibly preceded by '\*'). Per the RTF spec, ANY `\*` group is ignored
  /// regardless of the word; plain destinations are skipped only when the
  /// word is in [_destinations]. Non-destination groups just consume '{'.
  int _skipDestinationGroup(String src, int i) {
    final j = i + 1;
    if (j < src.length && src[j] == '\\') {
      var k = j + 1;
      final star = k < src.length && src[k] == '*';
      if (star) k++;
      if (k < src.length && src[k] == '\\') k++;
      final word = _readWord(src, k);
      if (word.isNotEmpty && (star || _isSkippedDestination(word))) {
        return _skipGroup(src, i);
      }
    }
    return i + 1;
  }

  /// Write a `\'hh` hex byte (latin1) at [i]; returns the index after it.
  int _writeHexEscape(StringBuffer sb, String src, int i) {
    final hex = src.substring(i + 2, (i + 4).clamp(0, src.length));
    final byte = int.tryParse(hex, radix: 16);
    if (byte != null) {
      sb.write(latin1.decode([byte]));
      return i + 4;
    }
    return i + 2;
  }

  bool _isEscapedLiteral(String next) =>
      next == '\\' || next == '{' || next == '}' || next == '~' ||
      next == '_' || next == '-';

  /// Write an escaped literal at [i] (`\\` `\{` `\}` `\~` `\_` `\-` — soft
  /// hyphen dropped); returns the index after it.
  int _writeEscapedLiteral(StringBuffer sb, String next, int i) {
    if (next != '-') sb.write(next == '~' || next == '_' ? ' ' : next);
    return i + 2;
  }

  /// Execute the control word starting at [start] ('\' + word + optional
  /// signed parameter); returns the index after the word and delimiter space.
  int _writeControlWord(
    StringBuffer sb,
    String src,
    int start,
    void Function(bool) toggleBold,
    void Function(bool) toggleItalic,
  ) {
    final word = _readWord(src, start + 1);
    final paramStart = start + 1 + word.length;
    final param = _readParam(src, paramStart);
    var cursor = paramStart + (param == null ? 0 : _paramLength(src, paramStart));
    // Optional delimiter space.
    if (cursor < src.length && src[cursor] == ' ') cursor++;
    switch (word) {
      case 'par':
      case 'line':
      case 'page':
      case 'row':
        sb.write('\n');
      case 'tab':
      case 'cell':
        sb.write(' ');
      case 'b':
        toggleBold(param == null || param > 0);
      case 'i':
        toggleItalic(param == null || param > 0);
      case 'ul':
        break; // underline ignored (plain text)
      case 'u':
        sb.write(String.fromCharCode(_unicodeCode(param)));
        cursor = _skipAnsiFallback(src, cursor);
      case 'bullet':
        sb.write('- ');
      case '~':
      case '_':
        sb.write(' ');
      case '-':
        break; // soft hyphen dropped
      default:
        break; // unknown control word — emit nothing
    }
    return cursor;
  }

  /// Unicode codepoint from a `\uN` parameter (negative → add 65536).
  int _unicodeCode(int? param) {
    var code = param ?? 0;
    if (code < 0) code += 65536;
    return code;
  }

  /// Skip the ANSI fallback character after a `\uN`: either a single char or
  /// `\'hh`; returns the index after it.
  int _skipAnsiFallback(String src, int cursor) {
    if (cursor < src.length) {
      if (src[cursor] == '\\' && cursor + 1 < src.length &&
          src[cursor + 1] == '\'' && cursor + 4 <= src.length) {
        return cursor + 4;
      }
      return cursor + 1;
    }
    return cursor;
  }

  /// Control word letters after '\'.
  String _readWord(String src, int start) {
    var k = start;
    while (k < src.length) {
      final c = src.codeUnitAt(k);
      if (c >= 0x61 && c <= 0x7A) {
        k++;
      } else {
        break;
      }
    }
    return src.substring(start, k);
  }

  /// Signed integer parameter (may be absent).
  int? _readParam(String src, int start) {
    var k = start;
    var sign = 1;
    if (k < src.length && src[k] == '-') {
      sign = -1;
      k++;
    }
    if (k >= src.length || src.codeUnitAt(k) < 0x30 || src.codeUnitAt(k) > 0x39) {
      return null;
    }
    var value = 0;
    while (k < src.length && src.codeUnitAt(k) >= 0x30 && src.codeUnitAt(k) <= 0x39) {
      value = value * 10 + (src.codeUnitAt(k) - 0x30);
      k++;
    }
    return sign * value;
  }

  /// Length in characters of the signed decimal parameter at [start]
  /// (sign + digits). Mirrors [_readParam]'s scan; only valid when
  /// [_readParam] did not return null.
  int _paramLength(String src, int start) {
    var k = start;
    if (k < src.length && src[k] == '-') k++;
    while (k < src.length && src.codeUnitAt(k) >= 0x30 && src.codeUnitAt(k) <= 0x39) {
      k++;
    }
    return k - start;
  }

  static const _destinations = {
    'fonttbl', 'colortbl', 'stylesheet', 'info', 'pict', 'themedata',
    'latentstyles', 'datastore', 'rsidtbl', 'listtable',
    'listoverridetable', 'generator', 'viewprops', 'header', 'footer',
    'footnote', 'annotation', 'pntext', 'pntxta', 'pntxtb',
  };

  bool _isSkippedDestination(String word) => _destinations.contains(word);

  /// True when [src] begins with the RTF group header `{\rtf` (after an
  /// optional BOM and leading whitespace). All RTF documents start with it.
  bool _hasRtfHeader(String src) {
    var k = src.startsWith('\uFEFF') ? 1 : 0;
    while (k < src.length) {
      final c = src[k];
      if (c != ' ' && c != '\t' && c != '\r' && c != '\n') break;
      k++;
    }
    return src.startsWith('{\\rtf', k);
  }

  /// Skip a group from the '{' at [start] to its matching '}' (returns the
  /// index AFTER the closing brace).
  int _skipGroup(String src, int start) {
    var depth = 0;
    var i = start;
    while (i < src.length) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return i + 1;
      }
      i++;
    }
    return src.length;
  }
}
