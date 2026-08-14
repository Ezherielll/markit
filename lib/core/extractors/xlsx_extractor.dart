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

/// Excel extractor (.xlsx/.xlsm) → markdown: one heading + one table per
/// sheet, in workbook order.
///
/// Supports shared strings, inline strings, formula strings, booleans, and
/// numeric cells; sparse rows are padded to the sheet's max column.
class XlsxExtractor implements FormatExtractor {
  const XlsxExtractor();

  @override
  InputFormat get format => InputFormat.excel;

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
          'Could not read the Excel file.',
        );
      }
      final archive = _openZip(raw);
      final (blocks, totalRows) = _collectBlocks(archive);
      if (blocks.isEmpty) {
        throw ConvertException(
          ConvertError.noText,
          'No text could be extracted from the Excel file.',
        );
      }

      var done = 0;
      for (final b in blocks) {
        if (isCancelled?.call() ?? false) break;
        writer.writeBlock(b);
        done++;
        onProgress?.call(done, blocks.length, 1, 0);
      }
      return ExtractionResult(itemCount: totalRows);
    });
  }

  /// Parse all sheets into blocks (bare-name heading + table per sheet, in
  /// workbook order) plus the total row count across sheets.
  (List<Block>, int) _collectBlocks(Archive archive) {
    final sharedStrings = _parseSharedStrings(_entryText(archive, 'xl/sharedStrings.xml'));
    final sheets = _resolveSheets(archive);
    if (sheets.isEmpty) {
      throw ConvertException(
        ConvertError.corrupt,
        'The Excel file has no worksheets.',
      );
    }

    final blocks = <Block>[];
    var totalRows = 0;
    for (final (name, path) in sheets) {
      final sheetXml = _entryText(archive, path);
      if (sheetXml == null) continue;
      final rows = _parseSheet(sheetXml, sharedStrings);
      if (rows.isEmpty) continue;
      blocks.add(Block(type: BlockType.heading, headingLevel: 1, lines: [name]));
      blocks.add(Block(type: BlockType.paragraph, lines: [tableToMarkdown(rows)]));
      totalRows += rows.length;
    }
    return (blocks, totalRows);
  }

  /// Ordered (name, path) sheet pairs: `xl/workbook.xml` sheets + their
  /// targets from `xl/_rels/workbook.xml.rels`. When the workbook has no
  /// resolvable sheets (or is absent), falls back to `xl/worksheets/sheet<N>`
  /// entries sorted numerically, named `Sheet <N>`.
  List<(String, String)> _resolveSheets(Archive archive) {
    final workbook = _parseWorkbook(_entryText(archive, 'xl/workbook.xml'));
    final rels = _parseOptionalXml(_entryText(archive, 'xl/_rels/workbook.xml.rels'));
    final sheets = <(String, String)>[];
    if (workbook != null) {
      final targets = _relTargets(rels);
      for (final s in workbook.descendants.whereType<XmlElement>()) {
        if (s.name.local != 'sheet') continue;
        final rid = s.getAttribute('id', namespace: '*');
        final target = rid == null ? null : targets[rid];
        if (target == null) continue;
        sheets.add((s.getAttribute('name', namespace: '*') ?? '', target));
      }
    }
    return sheets.isEmpty ? _fallbackSheets(archive) : sheets;
  }

  /// Parse `xl/workbook.xml`; missing entry → null, invalid XML → corrupt.
  XmlDocument? _parseWorkbook(String? xml) {
    if (xml == null) return null;
    try {
      return XmlDocument.parse(xml);
    } on XmlException catch (e) {
      throw ConvertException(
        ConvertError.corrupt,
        'The Excel workbook is not valid XML: ${e.message}',
      );
    }
  }

  /// Rel Id → resolved worksheet path; a leading '/' is stripped and
  /// relative targets are resolved against `xl/`.
  Map<String, String> _relTargets(XmlDocument? rels) {
    final targets = <String, String>{};
    if (rels == null) return targets;
    for (final r in rels.descendants.whereType<XmlElement>()) {
      if (r.name.local != 'Relationship') continue;
      final id = r.getAttribute('Id', namespace: '*');
      final target = r.getAttribute('Target', namespace: '*');
      if (id == null || target == null) continue;
      final t = target.startsWith('/') ? target.substring(1) : target;
      targets[id] = t.startsWith('xl/') ? t : 'xl/$t';
    }
    return targets;
  }

  /// Fallback when the workbook has no resolvable sheets: `sheet<N>.xml`
  /// entries sorted numerically, named `Sheet <N>`.
  List<(String, String)> _fallbackSheets(Archive archive) {
    final re = RegExp(r'^xl/worksheets/sheet(\d+)\.xml$');
    final sheets = <(int, String)>[];
    for (final f in archive.files) {
      if (!f.isFile) continue;
      final m = re.firstMatch(f.name);
      if (m == null) continue;
      sheets.add((int.parse(m.group(1)!), f.name));
    }
    sheets.sort((a, b) => a.$1.compareTo(b.$1));
    return [for (final s in sheets) ('Sheet ${s.$1}', s.$2)];
  }

  /// `<si>` entries → concatenated `<t>` text (single t or rich runs).
  List<String> _parseSharedStrings(String? xml) {
    final result = <String>[];
    final doc = _parseOptionalXml(xml);
    if (doc == null) return result;
    for (final si in doc.descendants.whereType<XmlElement>()) {
      if (si.name.local != 'si') continue;
      result.add(_concatTText(si));
    }
    return result;
  }

  /// Rows of a worksheet as padded string cells; empty rows are skipped.
  List<List<String>> _parseSheet(String sheetXml, List<String> shared) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(sheetXml);
    } on XmlException catch (e) {
      throw ConvertException(
        ConvertError.corrupt,
        'The Excel worksheet is not valid XML: ${e.message}',
      );
    }
    final sheetData = _firstLocal(doc.rootElement, 'sheetData');
    if (sheetData == null) return const [];

    final rows = <List<String>>[];
    var maxCol = 0;
    for (final row in sheetData.descendants.whereType<XmlElement>()) {
      if (row.name.local != 'row') continue;
      final cells = _rowCells(row, shared);
      if (cells.isEmpty) continue;
      if (cells.length > maxCol) maxCol = cells.length;
      rows.add(cells);
    }
    return [for (final r in rows) _padRow(r, maxCol)];
  }

  /// One row's cells, positioned by their `r` column ref; cells without an
  /// `r` take the previous column + 1. Rows with only empty cells → [].
  List<String> _rowCells(XmlElement row, List<String> shared) {
    final cells = <String>[];
    var prevCol = -1;
    for (final c in row.children.whereType<XmlElement>()) {
      if (c.name.local != 'c') continue;
      var col = _columnIndex(c.getAttribute('r', namespace: '*'));
      if (col < 0) col = prevCol + 1;
      while (cells.length < col) {
        cells.add('');
      }
      cells.add(_cellValue(c, shared));
      prevCol = col;
    }
    return cells.every((s) => s.isEmpty) ? const [] : cells;
  }

  /// Cell value by type: s → shared string, inlineStr → is/t text,
  /// str → raw v, b → TRUE/FALSE, default → raw v.
  String _cellValue(XmlElement c, List<String> shared) {
    final raw = _firstLocal(c, 'v')?.innerText ?? '';
    switch (c.getAttribute('t', namespace: '*')) {
      case 's':
        return _sharedText(raw, shared);
      case 'inlineStr':
        final isEl = _firstLocal(c, 'is');
        return isEl == null ? '' : _concatTText(isEl);
      case 'str':
        return raw;
      case 'b':
        return raw == '1' ? 'TRUE' : 'FALSE';
      default:
        return raw;
    }
  }

  /// Shared-string index → text; out-of-range / non-numeric → ''.
  String _sharedText(String raw, List<String> shared) {
    final index = int.tryParse(raw);
    if (index == null || index < 0 || index >= shared.length) return '';
    return shared[index];
  }

  /// Concatenated `<t>` texts under [parent].
  String _concatTText(XmlElement parent) => parent.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == 't')
      .map((e) => e.innerText)
      .join();

  /// Column letters → index (A=0, B=1, ... AA=26); no/invalid letters → -1.
  int _columnIndex(String? ref) {
    if (ref == null || ref.isEmpty) return -1;
    var col = 0;
    for (final ch in ref.codeUnits) {
      if (ch < 0x41 || ch > 0x5A) break;
      col = col * 26 + (ch - 0x40);
    }
    return col - 1;
  }

  /// Pad a row to [maxCol] with empty cells.
  List<String> _padRow(List<String> cells, int maxCol) {
    final padded = List<String>.filled(maxCol, '');
    for (var i = 0; i < cells.length; i++) {
      padded[i] = cells[i];
    }
    return padded;
  }

  /// Parse XML that may legitimately be absent (rels, shared strings).
  XmlDocument? _parseOptionalXml(String? xml) {
    if (xml == null) return null;
    try {
      return XmlDocument.parse(xml);
    } on XmlException {
      return null;
    }
  }

  String? _entryText(Archive archive, String name) {
    final entry = archive.files.where((f) => f.isFile && f.name == name).firstOrNull;
    if (entry == null) return null;
    return utf8.decode(entry.content as List<int>, allowMalformed: true);
  }

  Archive _openZip(Uint8List raw) {
    try {
      return ZipDecoder().decodeBytes(raw);
    } on ArchiveException {
      throw ConvertException(
        ConvertError.corrupt,
        'The Excel file is not a valid ZIP archive.',
      );
    }
  }

  XmlElement? _firstLocal(XmlElement root, String local) => root.descendants
      .whereType<XmlElement>()
      .where((e) => e.name.local == local)
      .firstOrNull;
}
