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

/// Fixture Fase A: hierarki heading H1(22pt)/H2(18pt)/H3(15pt) + body 12pt.
/// Tiap ukuran heading muncul >= 2 kali (syarat heading band).
///
/// PENTING (quirk pdfrx): proxy fontSize = tinggi bbox char, yang hanya
/// proporsional bila baris mengandung huruf berdescender (p/g/y/q/j).
/// Semua baris fixture sengaja memuat huruf tersebut.
List<PdfPageSpec> nestedHeadingsPages() {
  return [
    PdfPageSpec([
      PdfTextItem('Paper Overview and Goals', fontSize: 22, y: 750, bold: true),
      PdfTextItem('Background and Related Work', fontSize: 18, y: 700, bold: true),
      PdfTextItem('This paper presents the background of the project.', y: 660),
      PdfTextItem('The related work appears in the next pages.', y: 640),
      PdfTextItem('Motivation and Scope', fontSize: 15, y: 600, bold: true),
      PdfTextItem('The motivation is simple: people need better tools.', y: 560),
      PdfTextItem('The scope covers many types of documents.', y: 540),
      PdfTextItem('Approach and Design', fontSize: 15, y: 500, bold: true),
      PdfTextItem('The approach applies layout-aware parsing steps.', y: 460),
      PdfTextItem('The design keeps memory usage per page constant.', y: 440),
    ]),
    PdfPageSpec([
      PdfTextItem('Implementation Details', fontSize: 18, y: 700, bold: true),
      PdfTextItem('The implementation groups fragments into lines.', y: 660),
      PdfTextItem('Paragraph joining happens after line grouping.', y: 640),
      PdfTextItem('Evaluation Setup', fontSize: 15, y: 600, bold: true),
      PdfTextItem('The evaluation runs against a synthetic corpus.', y: 560),
      PdfTextItem('Every fixture is compared with a golden file.', y: 540),
      PdfTextItem('Appendix and References', fontSize: 22, y: 500, bold: true),
      PdfTextItem('The appendix contains supplementary material.', y: 460),
      PdfTextItem('References appear in the final section.', y: 440),
    ]),
  ];
}

/// Fixture Fase A: heading bernomor 1. / 1.1 / 1.1.1 dengan ukuran berbeda
/// (22pt/18pt/15pt) — menguji numbering pattern pada heading.
List<PdfPageSpec> numberedSectionsPages() {
  return [
    PdfPageSpec([
      PdfTextItem('1. Background and Scope', fontSize: 22, y: 750, bold: true),
      PdfTextItem('This section introduces the problem being solved.', y: 710),
      PdfTextItem('It explains the purpose and scope of the work.', y: 690),
      PdfTextItem('1.1 Related Papers', fontSize: 18, y: 650, bold: true),
      PdfTextItem('The related papers describe similar systems.', y: 610),
      PdfTextItem('They compare speed and output quality.', y: 590),
      PdfTextItem('1.1.1 Comparison Approach', fontSize: 15, y: 550, bold: true),
      PdfTextItem('The comparison approach uses the golden files.', y: 510),
    ]),
    PdfPageSpec([
      PdfTextItem('2. Experimental Setup', fontSize: 22, y: 750, bold: true),
      PdfTextItem('The experiments run on a synthetic corpus.', y: 710),
      PdfTextItem('The corpus pages are converted to markdown.', y: 690),
      PdfTextItem('2.1 Evaluation Approach', fontSize: 18, y: 650, bold: true),
      PdfTextItem('The metrics follow the project requirements.', y: 610),
      PdfTextItem('2.1.1 Paragraph Scoring', fontSize: 15, y: 550, bold: true),
      PdfTextItem('The scoring compares output with golden text.', y: 510),
      PdfTextItem('2.1.2 Heading Scoring', fontSize: 15, y: 470, bold: true),
      PdfTextItem('The heading scoring checks the level number.', y: 430),
    ]),
  ];
}

/// Fixture Fase A: ordered list 1. 2. 3. diikuti paragraf penutup.
List<PdfPageSpec> orderedListPages() {
  return [
    PdfPageSpec([
      PdfTextItem('Shopping List', fontSize: 18, y: 750, bold: true),
      PdfTextItem('1. Buy apples', y: 700),
      PdfTextItem('2. Buy bananas', y: 680),
      PdfTextItem('3. Buy oranges', y: 660),
      PdfTextItem('4. Buy grapes', y: 640),
      PdfTextItem('Remember to buy some grapes.', y: 600),
    ]),
    PdfPageSpec([
      PdfTextItem('Garden Tasks', fontSize: 18, y: 750, bold: true),
      PdfTextItem('1. Water the plants', y: 700),
      PdfTextItem('2. Take out the garbage', y: 680),
      PdfTextItem('3. Walk the dog', y: 660),
      PdfTextItem('That completes the weekly tasks.', y: 600),
    ]),
  ];
}
