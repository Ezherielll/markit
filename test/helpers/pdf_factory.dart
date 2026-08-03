import 'dart:convert';
import 'dart:typed_data';

class PdfTextItem {
  PdfTextItem(
    this.text, {
    this.fontSize = 12,
    this.x = 72,
    this.y = 700,
    this.bold = false,
  });

  final String text;
  final double fontSize;
  final double x;
  final double y;
  final bool bold;
}

class PdfPageSpec {
  PdfPageSpec(this.items);
  final List<PdfTextItem> items;
}

/// Membangun PDF sintetis valid (ASCII literal strings, Helvetica/Helvetica-Bold)
/// dengan xref table yang benar. Dipakai untuk fixture test & spike API.
Uint8List buildTestPdf({List<PdfPageSpec>? pages}) {
  final pageSpecs = pages ?? defaultPages();

  final objects = <String>[];
  objects.add('<< /Type /Catalog /Pages 2 0 R >>');

  final kids = pageSpecs.indexed.map((e) => '${3 + e.$1} 0 R').join(' ');
  objects.add('<< /Type /Pages /Kids [$kids] /Count ${pageSpecs.length} >>');

  final font1Obj = 3 + pageSpecs.length * 2;
  final font2Obj = 3 + pageSpecs.length * 2 + 1;

  for (var i = 0; i < pageSpecs.length; i++) {
    final contentObj = 3 + pageSpecs.length + i;
    objects.add(
      '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
      '/Contents $contentObj 0 R '
      '/Resources << /Font << /F1 $font1Obj 0 R /F2 $font2Obj 0 R >> >> >>',
    );
  }

  for (final page in pageSpecs) {
    final stream = _contentStream(page);
    objects.add('<< /Length ${ascii.encode(stream).length} >>\nstream\n$stream\nendstream');
  }

  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>');
  objects.add('<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold >>');

  final offsets = <int>[];
  final out = BytesBuilder();
  out.add(ascii.encode('%PDF-1.4\n'));
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.add(ascii.encode('${i + 1} 0 obj\n'));
    out.add(ascii.encode(objects[i]));
    out.add(ascii.encode('\nendobj\n'));
  }
  final xrefOffset = out.length;
  out.add(ascii.encode('xref\n0 ${objects.length + 1}\n'));
  out.add(ascii.encode('0000000000 65535 f \n'));
  for (final off in offsets) {
    out.add(ascii.encode('${off.toString().padLeft(10, '0')} 00000 n \n'));
  }
  out.add(ascii.encode('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\nstartxref\n$xrefOffset\n%%EOF'));
  return out.takeBytes();
}

String _contentStream(PdfPageSpec page) {
  final buf = StringBuffer();
  for (final item in page.items) {
    final font = item.bold ? 'F2' : 'F1';
    final escaped = item.text
        .replaceAll(r'\', r'\\')
        .replaceAll('(', r'\(')
        .replaceAll(')', r'\)');
    buf.writeln(
      'BT /$font ${item.fontSize} Tf 1 0 0 1 ${item.x} ${item.y} Tm ($escaped) Tj ET',
    );
  }
  return buf.toString();
}

List<PdfPageSpec> defaultPages() {
  return [
    PdfPageSpec([
      PdfTextItem('The Quick Brown Fox', fontSize: 24, y: 700, bold: true),
      PdfTextItem('This is the first paragraph of the sample document.', y: 660),
      PdfTextItem('It spans multiple lines of body text.', y: 640),
      PdfTextItem('- Item one', y: 600),
      PdfTextItem('- Item two', y: 580),
    ]),
    PdfPageSpec([
      PdfTextItem('Page two continues the story.', y: 700),
      PdfTextItem('With a second paragraph block.', y: 680),
    ]),
    PdfPageSpec([
      PdfTextItem('Chapter Two', fontSize: 18, y: 700, bold: true),
      PdfTextItem('Final paragraph of the fixture.', y: 660),
    ]),
  ];
}

/// Generator dokumen besar (untuk benchmark/decision gate): [pageCount]
/// halaman, tiap halaman berisi heading bab + beberapa paragraf body + list.
/// Bab berganti tiap [chapterEvery] halaman.
List<PdfPageSpec> largeBookPages(int pageCount, {int chapterEvery = 20}) {
  final pages = <PdfPageSpec>[];
  for (var i = 0; i < pageCount; i++) {
    final chapter = (i ~/ chapterEvery) + 1;
    final items = <PdfTextItem>[];
    if (i % chapterEvery == 0) {
      items.add(PdfTextItem('Chapter $chapter', fontSize: 22, y: 700, bold: true));
    }
    items.addAll([
      PdfTextItem('Page $i paragraph one with some body text that fills a line.', y: 660),
      PdfTextItem('It continues onto a second line of the paragraph.', y: 640),
      PdfTextItem('A second paragraph follows after a small gap.', y: 600),
      PdfTextItem('- Bullet number one on page $i', y: 560),
      PdfTextItem('- Bullet number two on page $i', y: 540),
    ]);
    pages.add(PdfPageSpec(items));
  }
  return pages;
}
