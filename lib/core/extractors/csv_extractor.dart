import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_writer.dart';

/// Ekstraktor CSV → tabel markdown (baris pertama = header).
///
/// Mendukung quoted field (`"a,b"` = satu kolom), CRLF, baris kosong.
class CsvExtractor implements FormatExtractor {
  const CsvExtractor();

  @override
  InputFormat get format => InputFormat.csv;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
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
    final dataRows = rows.where((r) => r.any((c) => c.trim().isNotEmpty)).toList();
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
    onProgress?.call(dataRows.length, dataRows.length);
    return ExtractionResult(itemCount: dataRows.length);
  }

  String? _readRaw(Uint8List? bytes, String? path) {
    if (bytes != null) {
      // CSV sering latin1/ANSI — decode dengan utf8 lalu fallback.
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

  /// Parse CSV sederhana: dukung quoted field & CRLF. Baris kosong
  /// (semua kolom kosong) dilewati.
  List<List<String>> _parseCsv(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    var field = StringBuffer();
    var inQuotes = false;
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else {
        switch (c) {
          case '"':
            inQuotes = true;
          case ',':
            row.add(field.toString());
            field = StringBuffer();
          case '\r':
            // skip (CRLF dihandle saat '\n')
          case '\n':
            row.add(field.toString());
            field = StringBuffer();
            if (row.any((f) => f.trim().isNotEmpty)) {
              rows.add(row);
            }
            row = [];
          default:
            field.write(c);
        }
      }
      i++;
    }
    if (row.isNotEmpty || field.isNotEmpty) {
      row.add(field.toString());
      if (row.any((f) => f.trim().isNotEmpty)) rows.add(row);
    }
    return rows;
  }

  String _escapeCell(String cell) =>
      cell.replaceAll('|', r'\|').replaceAll('\n', ' ');
}
