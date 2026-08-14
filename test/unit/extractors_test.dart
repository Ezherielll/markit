import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/csv_extractor.dart';
import 'package:markit/core/output.dart';

Uint8List _utf8(String s) => Uint8List.fromList(utf8.encode(s));

Future<String> _run(
  Object extractor,
  Uint8List bytes,
) async {
  final output = MemoryOutput();
  final result = await _extract(extractor, bytes, output);
  expect(result, isNotNull);
  return output.content;
}

Future<dynamic> _extract(
  Object extractor,
  Uint8List bytes,
  MemoryOutput output,
) {
  return switch (extractor) {
    CsvExtractor() =>
      extractor.extract(bytes: bytes, output: output),
    _ => throw UnsupportedError('unreachable'),
  };
}

void main() {
  group('CsvExtractor', () {
    test('header + rows → tabel markdown', () async {
      final md = await _run(
        const CsvExtractor(),
        _utf8('Name,Age\nAlice,30\nBob,25'),
      );
      expect(
        md,
        contains('| Name | Age |\n| --- | --- |\n| Alice | 30 |\n| Bob | 25 |'),
      );
    });

    test('quoted field dengan koma', () async {
      final md = await _run(
        const CsvExtractor(),
        _utf8('A,B\n"x,y",z'),
      );
      expect(md, contains('| x,y | z |'));
    });

    test('CRLF + baris kosong dilewati', () async {
      final md = await _run(
        const CsvExtractor(),
        _utf8('A,B\r\n1,2\r\n\r\n3,4'),
      );
      expect(md, contains('| 1 | 2 |'));
      expect(md, contains('| 3 | 4 |'));
    });

    test('CR tunggal (classic Mac) mengakhiri baris (regresi \\r)', () async {
      final md = await _run(
        const CsvExtractor(),
        _utf8('a,b\rc,d'),
      );
      expect(md, contains('| a | b |'));
      expect(md, contains('| c | d |'));
    });

    test('empty → ConvertException noText', () async {
      expect(
        () => _run(const CsvExtractor(), _utf8('')),
        throwsA(isA<ConvertException>()),
      );
    });
  });
}
