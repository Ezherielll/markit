import 'dart:io';

import '../test/helpers/pdf_factory.dart';

/// Generator korpus sintetis (Task 14): deterministik, tanpa download.
///
///   dart run benchmark/make_corpus.dart
///
/// Menghasilkan:
///   corpus/pdfs/book_single.pdf     — buku satu kolom, heading jelas (best case)
///   corpus/pdfs/simple_table.pdf    — tabel sederhana 3 kolom (Fase C)
///   corpus/pdfs/nested_list.pdf     — nested list flat + 1 level (Fase C)
///   corpus/golden/{name}.md         — golden reference manual
void main() {
  Directory('corpus/pdfs').createSync(recursive: true);
  Directory('corpus/golden').createSync(recursive: true);

  _write('book_single.pdf', buildTestPdf(pages: largeBookPages(60, chapterEvery: 15)));
  // PERUBAHAN: ganti with_tables dengan simple_table (golden yang benar)
  _write('simple_table.pdf', buildTestPdf(pages: simpleTablePages()));
  _write('nested_list.pdf', buildTestPdf(pages: nestedListPages()));
  // Fase A fixtures
  _write('nested_headings.pdf', buildTestPdf(pages: nestedHeadingsPages()));
  _write('numbered_sections.pdf', buildTestPdf(pages: numberedSectionsPages()));
  _write('ordered_list.pdf', buildTestPdf(pages: orderedListPages()));
  // Fase B fixtures
  _write('multi_column_paper.pdf', buildTestPdf(pages: twoColumnPages()));
  _write('header_footer.pdf', buildTestPdf(pages: headerFooterPages()));

  stdout.writeln('corpus sintetis dibuat di corpus/pdfs/ + corpus/golden/');
}

void _write(String name, List<int> bytes) {
  File('corpus/pdfs/$name').writeAsBytesSync(bytes);
}
