import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../output.dart';

/// CSV extractor → markdown table (first row = header).
///
/// Supports quoted fields (`"a,b"` = one column), CRLF, empty rows.
class CsvExtractor implements FormatExtractor {
  const CsvExtractor();

  @override
  InputFormat get format => InputFormat.csv;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required OutputTarget output,
    void Function(int done, int total, int phase, int elapsedMs)? onProgress,
    bool Function()? isCancelled,
  }) {
    return withMarkdownWriter(output, run: (writer) async {
      final raw = _readRaw(bytes, path);
      if (raw == null) {
        throw ConvertException(
          ConvertError.corrupt,
          'Could not read the CSV file.',
        );
      }
      if (isCancelled?.call() ?? false) {
        return ExtractionResult(itemCount: 0);
      }

      final rows = _parseCsv(_stripBom(raw));
      final dataRows =
          rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
      if (dataRows.isEmpty) {
        throw ConvertException(ConvertError.noText, 'The CSV file is empty.');
      }

      final header = dataRows.first;
      final body = dataRows.skip(1).toList();

      final sb = StringBuffer()
        ..writeln('| ${header.map(_escapeCell).join(' | ')} |')
        ..writeln('| ${header.map((_) => '---').join(' | ')} |');
      for (final row in body) {
        sb.writeln('| ${row.map(_escapeCell).join(' | ')} |');
        if (isCancelled?.call() ?? false) break;
      }

      writer.writeRaw(sb.toString().trimRight());
      onProgress?.call(dataRows.length, dataRows.length, 1, 0);
      return ExtractionResult(itemCount: dataRows.length);
    });
  }

  String? _readRaw(Uint8List? bytes, String? path) {
    if (bytes != null) {
      // CSV is often latin1/ANSI — try decoding with utf8 then fallback.
      try {
        return utf8.decode(bytes);
      } on FormatException {
        return latin1.decode(bytes);
      }
    }
    if (path != null && File(path).existsSync()) {
      final raw = File(path).readAsBytesSync();
      try {
        return utf8.decode(raw);
      } on FormatException {
        return latin1.decode(raw);
      }
    }
    return null;
  }

  String _stripBom(String s) {
    if (s.startsWith('\uFEFF')) return s.substring(1);
    return s;
  }

  /// Simple CSV parser: supports quoted fields & CRLF. Empty rows
  /// (all empty columns) are skipped.
  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var inQuotes = false;
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (inQuotes) {
        switch (_quoteStep(c, text, i, field)) {
          case _QuoteStep.escaped:
            i++; // skip second quote of double quote ('""' → '"')
          case _QuoteStep.closed:
            inQuotes = false;
          case _QuoteStep.plain:
            break;
        }
      } else {
        switch (c) {
          case '"':
            inQuotes = true;
          case ',':
            _flushCell(row, field);
            field = StringBuffer();
          case '\r':
          // Baseline behavior: empty case → fall-through; \r ends line.
          case '\n':
            _flushCell(row, field);
            field = StringBuffer();
            _addRowIfNonEmpty(rows, row);
            row = [];
          default:
            field.write(c);
        }
      }
      i++;
    }
    if (row.isNotEmpty || field.isNotEmpty) {
      _flushCell(row, field);
      _addRowIfNonEmpty(rows, row);
    }
    return rows;
  }

  /// Processing step for a single character inside a quoted field.
  _QuoteStep _quoteStep(String c, String text, int i, StringBuffer field) {
    if (c != '"') {
      field.write(c);
      return _QuoteStep.plain;
    }
    if (i + 1 < text.length && text[i + 1] == '"') {
      field.write('"');
      return _QuoteStep.escaped;
    }
    return _QuoteStep.closed;
  }

  /// Flush current field to row (comma separator or end of line).
  void _flushCell(List<String> row, StringBuffer field) {
    row.add(field.toString());
  }

  /// Add row only if it contains non-empty columns (empty rows skipped).
  void _addRowIfNonEmpty(List<List<String>> rows, List<String> row) {
    if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
  }

  String _escapeCell(String cell) =>
      cell.replaceAll('|', r'\|').replaceAll('\n', ' ');
}

/// Processing step for a single character inside a quoted field.
enum _QuoteStep { plain, escaped, closed }
