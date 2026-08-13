import 'dart:io';

import '../test/helpers/pdf_factory.dart';

/// Synthetic corpus generator: deterministic, zero downloads.
///
///   dart run benchmark/make_corpus.dart
///
/// Generates:
///   corpus/pdfs/book_single.pdf     — single-column book, clear headings (best case)
///   corpus/pdfs/simple_table.pdf    — simple 3-column table
///   corpus/pdfs/nested_list.pdf     — nested list flat + 1 level
///   corpus/pdfs/multi_page_table.pdf — table spanning 2 pages
///   corpus/golden/{name}.md         — manual golden reference
void main() {
  Directory('corpus/pdfs').createSync(recursive: true);
  Directory('corpus/golden').createSync(recursive: true);

  _write('book_single.pdf', buildTestPdf(pages: largeBookPages(60, chapterEvery: 15)));
  _write('simple_table.pdf', buildTestPdf(pages: simpleTablePages()));
  _write('nested_list.pdf', buildTestPdf(pages: nestedListPages()));
  // Phase A fixtures
  _write('nested_headings.pdf', buildTestPdf(pages: nestedHeadingsPages()));
  _write('numbered_sections.pdf', buildTestPdf(pages: numberedSectionsPages()));
  _write('ordered_list.pdf', buildTestPdf(pages: orderedListPages()));
  // Phase B fixtures
  _write('multi_column_paper.pdf', buildTestPdf(pages: twoColumnPages()));
  _write('header_footer.pdf', buildTestPdf(pages: headerFooterPages()));
  // Phase D fixtures
  _write('multi_page_table.pdf', buildTestPdf(pages: multiPageTablePages()));
  _write('mixed_table.pdf', buildTestPdf(pages: mixedTablePages()));

  stdout.writeln('synthetic corpus generated in corpus/pdfs/ + corpus/golden/');
}

void _write(String name, List<int> bytes) {
  File('corpus/pdfs/$name').writeAsBytesSync(bytes);
}
