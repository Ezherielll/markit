import 'dart:io';

/// Generator golden reference untuk korpus sintetis (Task 14).
///
/// Golden ditulis dari SPESIFIKASI INPUT (pdf_factory) — bukan dari output
/// pipeline — sehingga independen dan menjadi ground truth evaluasi.
///   dart run benchmark/make_golden.dart
///
/// CATATAN (Fase C): konten golden Fase A/B/C kini sumber tunggalnya di
/// corpus/golden/ (ditulis manual bersama fixture). File ini hanya dipakai
/// untuk regenerate golden lama (book_single) dan mereproduksi golden
/// Fase C dari spesifikasi.
void main() {
  Directory('corpus/golden').createSync(recursive: true);

  _writeGolden('book_single.md', _bookSingleGolden(60, chapterEvery: 15));
  _writeGolden('simple_table.md', _simpleTableGolden());
  _writeGolden('nested_list.md', _nestedListGolden());

  stdout.writeln('golden dibuat di corpus/golden/');
}

void _writeGolden(String name, String content) {
  File('corpus/golden/$name').writeAsStringSync(content);
}

String _bookSingleGolden(int pageCount, {required int chapterEvery}) {
  final sb = StringBuffer();
  for (var i = 0; i < pageCount; i++) {
    if (i % chapterEvery == 0) {
      sb.writeln('# Chapter ${(i ~/ chapterEvery) + 1}');
      sb.writeln();
    }
    sb.writeln('Page $i paragraph one with some body text that fills a line. '
        'It continues onto a second line of the paragraph.');
    sb.writeln();
    sb.writeln('A second paragraph follows after a small gap.');
    sb.writeln();
    sb.writeln('- Bullet number one on page $i');
    sb.writeln();
    sb.writeln('- Bullet number two on page $i');
    sb.writeln();
  }
  return sb.toString();
}

String _simpleTableGolden() {
  return [
    '# Inventory Report',
    '',
    '| Name | Qty | Price |',
    '| --- | --- | --- |',
    '| Apples | 10 | 2.50 |',
    '| Bananas | 20 | 1.75 |',
    '| Cherries | 5 | 8.00 |',
    '',
    'End of table with plain text after.',
    '',
  ].join('\n');
}

String _nestedListGolden() {
  return [
    '# Nested List Example',
    '',
    '- Pears',
    '  - Apples',
    '  - Oranges',
    '- Vegetables',
    '  - Carrots',
    '- Grapes',
    '- Dairy',
    '',
  ].join('\n');
}
