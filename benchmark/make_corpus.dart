import 'dart:io';

import '../test/helpers/pdf_factory.dart';

/// Generator korpus sintetis (Task 14): deterministik, tanpa download.
///
///   dart run benchmark/make_corpus.dart
///
/// Menghasilkan:
///   corpus/pdfs/book_single.pdf     — buku satu kolom, heading jelas (best case)
///   corpus/pdfs/with_tables.pdf     — baris berpola tabel (grid sederhana)
///   corpus/golden/{name}.md         — golden reference manual
void main() {
  Directory('corpus/pdfs').createSync(recursive: true);
  Directory('corpus/golden').createSync(recursive: true);

  _write('book_single.pdf', buildTestPdf(pages: largeBookPages(60, chapterEvery: 15)));
  _write('with_tables.pdf', buildTestPdf(pages: _tablePdf()));

  stdout.writeln('corpus sintetis dibuat di corpus/pdfs/ + corpus/golden/');
}

void _write(String name, List<int> bytes) {
  File('corpus/pdfs/$name').writeAsBytesSync(bytes);
}

List<PdfPageSpec> _tablePdf() {
  final pages = <PdfPageSpec>[];
  final rows = [
    ('Name', 'Qty', 'Price'),
    ('Apples', '10', '2.50'),
    ('Bananas', '20', '1.75'),
    ('Cherries', '5', '8.00'),
  ];
  var y = 700.0;
  final items = <PdfTextItem>[
    PdfTextItem('Inventory Report', fontSize: 20, y: 740, bold: true),
  ];
  for (final row in rows) {
    items.add(
      PdfTextItem('${row.$1.padRight(12)}  ${row.$2.padRight(6)}  ${row.$3}',
          x: 72, y: y),
    );
    y -= 22;
  }
  items.add(PdfTextItem('End of table with plain text after.', y: y - 10));
  pages.add(PdfPageSpec(items));
  return pages;
}
