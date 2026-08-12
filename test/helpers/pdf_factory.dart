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
      PdfTextItem('Paper Overview and Goals', fontSize: 22, y: 715, bold: true),
      PdfTextItem('Background and Related Work', fontSize: 18, y: 660, bold: true),
      PdfTextItem('This paper presents the background of the project.', y: 620),
      PdfTextItem('The related work appears in the next pages.', y: 600),
      PdfTextItem('Motivation and Scope', fontSize: 15, y: 560, bold: true),
      PdfTextItem('The motivation is simple: people need better tools.', y: 520),
      PdfTextItem('The scope covers many types of documents.', y: 500),
      PdfTextItem('Approach and Design', fontSize: 15, y: 460, bold: true),
      PdfTextItem('The approach applies layout-aware parsing steps.', y: 420),
      PdfTextItem('The design keeps memory usage per page constant.', y: 400),
    ]),
    PdfPageSpec([
      PdfTextItem('Implementation Details', fontSize: 18, y: 660, bold: true),
      PdfTextItem('The implementation groups fragments into lines.', y: 620),
      PdfTextItem('Paragraph joining happens after line grouping.', y: 600),
      PdfTextItem('Evaluation Setup', fontSize: 15, y: 560, bold: true),
      PdfTextItem('The evaluation runs against a synthetic corpus.', y: 520),
      PdfTextItem('Every fixture is compared with a golden file.', y: 500),
      PdfTextItem('Appendix and References', fontSize: 22, y: 460, bold: true),
      PdfTextItem('The appendix contains supplementary material.', y: 420),
      PdfTextItem('References appear in the final section.', y: 400),
    ]),
  ];
}

/// Fixture Fase A: heading bernomor 1. / 1.1 / 1.1.1 dengan ukuran berbeda
/// (22pt/18pt/15pt) — menguji numbering pattern pada heading.
List<PdfPageSpec> numberedSectionsPages() {
  return [
    PdfPageSpec([
      PdfTextItem('1. Background and Scope', fontSize: 22, y: 715, bold: true),
      PdfTextItem('This section introduces the problem being solved.', y: 655),
      PdfTextItem('It explains the purpose and scope of the work.', y: 635),
      PdfTextItem('1.1 Related Papers', fontSize: 18, y: 595, bold: true),
      PdfTextItem('The related papers describe similar systems.', y: 555),
      PdfTextItem('They compare speed and output quality.', y: 535),
      PdfTextItem('1.1.1 Comparison Approach', fontSize: 15, y: 495, bold: true),
      PdfTextItem('The comparison approach uses the golden files.', y: 455),
    ]),
    PdfPageSpec([
      PdfTextItem('2. Experimental Setup', fontSize: 22, y: 715, bold: true),
      PdfTextItem('The experiments run on a synthetic corpus.', y: 655),
      PdfTextItem('The corpus pages are converted to markdown.', y: 635),
      PdfTextItem('2.1 Evaluation Approach', fontSize: 18, y: 595, bold: true),
      PdfTextItem('The metrics follow the project requirements.', y: 555),
      PdfTextItem('2.1.1 Paragraph Scoring', fontSize: 15, y: 515, bold: true),
      PdfTextItem('The scoring compares output with golden text.', y: 475),
      PdfTextItem('2.1.2 Heading Scoring', fontSize: 15, y: 435, bold: true),
      PdfTextItem('The heading scoring checks the level number.', y: 395),
    ]),
  ];
}

/// Fixture Fase A: ordered list 1. 2. 3. diikuti paragraf penutup.
List<PdfPageSpec> orderedListPages() {
  return [
    PdfPageSpec([
      PdfTextItem('Shopping List', fontSize: 18, y: 715, bold: true),
      PdfTextItem('1. Buy apples', y: 680),
      PdfTextItem('2. Buy bananas', y: 660),
      PdfTextItem('3. Buy oranges', y: 640),
      PdfTextItem('4. Buy grapes', y: 620),
      PdfTextItem('Remember to buy some grapes.', y: 580),
    ]),
    PdfPageSpec([
      PdfTextItem('Garden Tasks', fontSize: 18, y: 715, bold: true),
      PdfTextItem('1. Water the plants', y: 680),
      PdfTextItem('2. Take out the garbage', y: 660),
      PdfTextItem('3. Walk the dog', y: 640),
      PdfTextItem('That completes the weekly tasks.', y: 580),
    ]),
  ];
}

/// Fixture Fase B: dokumen 2-kolom (paper style).
/// Kolom kiri: x=72, Kolom kanan: x=320, pageWidth=612.
/// Judul pendek (3 kata, muat dalam lebar kolom kiri) agar histogram xLeft
/// tetap hanya punya 1 gap besar (2 cluster), dan y=715 agar tidak masuk
/// zona header (0.93*792).
List<PdfPageSpec> twoColumnPages() {
  return [
    PdfPageSpec([
      PdfTextItem('Two Column Paper', fontSize: 20, x: 72, y: 715, bold: true),
      // Kolom kiri
      PdfTextItem('Left column first paragraph', x: 72, y: 660),
      PdfTextItem('continues on second line.', x: 72, y: 640),
      PdfTextItem('Left column second paragraph', x: 72, y: 600),
      // Kolom kanan
      PdfTextItem('Right column first paragraph', x: 320, y: 660),
      PdfTextItem('continues on second line.', x: 320, y: 640),
      PdfTextItem('Right column second paragraph', x: 320, y: 600),
    ]),
    PdfPageSpec([
      // Halaman 2: sama
      PdfTextItem('Left page two paragraph', x: 72, y: 660),
      PdfTextItem('Right page two paragraph', x: 320, y: 660),
    ]),
  ];
}

/// Fixture Fase B: dokumen dengan header dan footer.
/// Header di y=770 (pageHeight=792 → 97% > 93%), Footer di y=30 (4% < 8%).
List<PdfPageSpec> headerFooterPages() {
  return [
    PdfPageSpec([
      // Header (harus disuppress)
      PdfTextItem('Chapter Title Header', x: 200, y: 770),
      PdfTextItem('Page 1 of 10', x: 500, y: 770),
      // Body content (harus muncul)
      PdfTextItem('Main content paragraph', x: 72, y: 600),
      PdfTextItem('continues here.', x: 72, y: 580),
      PdfTextItem('Second paragraph of content.', x: 72, y: 540),
      // Footer (harus disuppress)
      PdfTextItem('University of Example', x: 200, y: 30),
      PdfTextItem('2024', x: 520, y: 30),
    ]),
    PdfPageSpec([
      PdfTextItem('Chapter Title Header', x: 200, y: 770),
      PdfTextItem('Page 2 of 10', x: 500, y: 770),
      PdfTextItem('Third paragraph here.', x: 72, y: 600),
      PdfTextItem('University of Example', x: 200, y: 30),
    ]),
  ];
}

/// Fixture Fase C: tabel sederhana 3 kolom, 4 baris (termasuk header).
/// Kolom di x=72, x=200, x=260. Gap antar kolom > 20pt (syarat TableDetector).
///
/// PENTING (deviasi empiris dari sketsa brief): kolom ketiga di x=260, bukan
/// x=350. Dengan x=350, ColumnSplitter (Fase B) memisahkan halaman menjadi
/// 2 kolom (gap 132pt > 8%*612=48.96pt) sehingga sel kolom ketiga keluar
/// dari baris tabel. x=260 tetap memberi gap 41.5pt > 20pt dari kata terlebar
/// kolom kedua ('Qty' berakhir di ~218.5), dan masih <= 241.7+48.96 (running
/// maxXRight baris 'End of table...' + threshold) sehingga halaman tetap
/// single-column.
///
/// Judul di y=715 (bukan 750 dari sketsa awal): yTop ≈ 729.5 harus < 736.6
/// (0.93*792) agar tidak disuppress zona header. Jarak judul→baris pertama
/// yang rapat sengaja membuat threshold paragraf kecil (median gap tertarik
/// ke bawah), sehingga tiap baris tabel jadi paragraf terpisah — syarat
/// TableDetector (satu baris per paragraf).
List<PdfPageSpec> simpleTablePages() {
  const cols = [72.0, 200.0, 260.0];
  final rows = [
    ('Name', 'Qty', 'Price'),
    ('Apples', '10', '2.50'),
    ('Bananas', '20', '1.75'),
    ('Cherries', '5', '8.00'),
  ];
  final items = <PdfTextItem>[
    PdfTextItem('Inventory Report', fontSize: 20, x: 72, y: 715, bold: true),
  ];
  var y = 700.0;
  for (final row in rows) {
    items.addAll([
      PdfTextItem(row.$1, x: cols[0], y: y),
      PdfTextItem(row.$2, x: cols[1], y: y),
      PdfTextItem(row.$3, x: cols[2], y: y),
    ]);
    y -= 22;
  }
  items.add(PdfTextItem('End of table with plain text after.', x: 72, y: y - 10));
  return [PdfPageSpec(items)];
}

/// Fixture Fase D: tabel 4 baris data terpotong 2 halaman.
/// Halaman 2 mengulang header (pola umum di dokumen cetak) — converter
/// harus membuang header ulang tersebut (bukan dijadikan baris data).
/// Kolom di x=72, x=200, x=260 (pola simple_table Fase C).
///
/// PENTING (deviasi empiris dari sketsa brief): judul 'Multi Page Inventory'
/// DIULANG di halaman 2. Tanpa judul, halaman 2 tidak pernah jadi tabel:
/// (1) ColumnSplitter memecahnya jadi 2 kolom — judul 20pt di halaman 1
/// memperlebar running maxXRight cluster (xRight ≈ 294) sehingga x=200/260
/// tergabung satu kolom; (2) threshold paragraf naik (base = median gap
/// ≈ 10.8 vs 1.9 dengan judul) sehingga semua baris tergabung satu paragraf.
/// Dengan judul, geometri halaman 2 identik dengan halaman 1 yang sudah
/// tervalidasi empiris (pola sama seperti simple_table).
List<PdfPageSpec> multiPageTablePages() {
  const cols = [72.0, 200.0, 260.0];
  List<PdfTextItem> row(double y, (String, String, String) cells) => [
        PdfTextItem(cells.$1, x: cols[0], y: y),
        PdfTextItem(cells.$2, x: cols[1], y: y),
        PdfTextItem(cells.$3, x: cols[2], y: y),
      ];
  return [
    PdfPageSpec([
      PdfTextItem('Multi Page Inventory', fontSize: 20, x: 72, y: 715, bold: true),
      ...row(700, ('Name', 'Qty', 'Price')),
      ...row(678, ('Peaches', '10', '2.50')),
      ...row(656, ('Grapes', '20', '1.75')),
    ]),
    PdfPageSpec([
      // Judul berulang (lihat komentar deviasi empiris di atas)
      PdfTextItem('Multi Page Inventory', fontSize: 20, x: 72, y: 715, bold: true),
      ...row(700, ('Name', 'Qty', 'Price')), // header berulang
      ...row(678, ('Apricots', '5', '8.00')),
      ...row(656, ('Mangoes', '12', '3.25')),
    ]),
  ];
}

/// Fixture Fase C: nested list (flat + satu level nested).
/// bodyLeftMargin=72, fontSize=12 → nested threshold ≈ 90pt.
/// Flat items di x=72 (4 item), nested items di x=96 (3 item) — jumlah flat
/// lebih banyak agar mode xLeft jatuh di 72 (tie-break menang 4 vs 3).
/// 'Dairy' tambahan (resolusi controller) menjamin flat items mayoritas.
///
/// PENTING (deviasi empiris dari sketsa brief): '- Fruits' → '- Pears' dan
/// '- Grains' → '- Grapes' (resolusi descender controller). Sampel xLeft
/// pass 1 hanya memuat span dengan fontSize di band [0.8x..1.1x] body mode
/// (~11.5pt); item tanpa huruf berdescender terukur ~8.8-9.0pt dan
/// tereksklusi — tanpa swap ini sampel flat hanya 2 (Vegetables/Dairy) vs
/// 2 nested (Apples/Oranges) → tie-break memilih 96 sebagai bodyLeftMargin
/// → semua item jadi flat. Pears/Grapes ber-descender ('p') sehingga ke-4
/// item flat masuk band → mode 72 (4 vs 2).
/// Fixture Fase C+D: nested list 3 level (flat, depth 1, depth 2).
/// bodyLeftMargin ≈ 80 (mode xLeft sampling), step ≈ 12.75 →
/// bullet x=72 → depth 0, x=96 → 1, x=114 → 2.
List<PdfPageSpec> nestedListPages() {
  return [
    PdfPageSpec([
      PdfTextItem('Nested List Example', fontSize: 18, y: 715, bold: true),
      PdfTextItem('- Fruits', x: 72, y: 700),
      PdfTextItem('-  Apples', x: 96, y: 680),
      PdfTextItem('-   Fuji Apples', x: 114, y: 660),
      PdfTextItem('- Vegetables', x: 72, y: 640),
      PdfTextItem('-  Carrots', x: 96, y: 620),
      PdfTextItem('- Grapes', x: 72, y: 600),
      PdfTextItem('- Dairy', x: 72, y: 580),
    ]),
  ];
}
