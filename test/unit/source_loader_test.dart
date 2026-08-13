import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/core/text_truncate.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/source/source_loader.dart';

import '../helpers/docx_factory.dart';
import '../helpers/pdf_factory.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_src_test');
  });

  tearDown(() async {
    for (var i = 0; i < 5; i++) {
      try {
        await tmp.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  Future<String> writeFile(String name, String content) async {
    final p = '${tmp.path}/$name';
    File(p).writeAsBytesSync(utf8.encode(content));
    return p;
  }

  group('loadSourceText', () {
    test('path: konten persis, tidak terpotong', () async {
      final path = await writeFile('a.csv', 'halo\ndunia\n');
      final r = await loadSourceText(
        PdfInput(name: 'a.csv', path: path, format: InputFormat.csv),
      );
      expect(r, isA<SourceText>());
      expect(r.content, 'halo\ndunia\n');
      expect(r.truncated, isFalse);
    });

    test('konten > maxChars: terpotong di batas baris', () async {
      final big = List.filled(8000, 'baris ke-N\n').join();
      final path = await writeFile('big.csv', big);
      final r = await loadSourceText(
        PdfInput(name: 'big.csv', path: path, format: InputFormat.csv),
        maxChars: 1024,
      );
      expect(r.truncated, isTrue);
      expect(r.content.length, lessThanOrEqualTo(1024));
      expect(r.content.endsWith('\n'), isTrue);
      // Tidak ada baris terpotong di tengah.
      expect(r.content.split('\n').every((l) => l.isEmpty || l.startsWith('baris')),
          isTrue);
    });

    test('bytes (web): konten sama dengan path', () async {
      final r = await loadSourceText(
        PdfInput(
          name: 'a.csv',
          bytes: Uint8List.fromList(utf8.encode('a,b\n1,2\n')),
          format: InputFormat.csv,
        ),
      );
      expect(r.content, 'a,b\n1,2\n');
      expect(r.truncated, isFalse);
    });

    test('bytes rusak (bukan UTF-8): tidak throw, allowMalformed', () async {
      final r = await loadSourceText(
        PdfInput(
          name: 'b.bin',
          bytes: Uint8List.fromList([0xFF, 0xFE, 0x00, 0x41, 0x61]),
          format: InputFormat.rtf,
        ),
      );
      expect(r, isA<SourceText>());
    });

    test('file tidak ada: SourceLoadException', () async {
      expect(
        () => loadSourceText(
          PdfInput(name: 'x.csv', path: '${tmp.path}/missing.csv'),
        ),
        throwsA(isA<SourceLoadException>()),
      );
    });

    test('tanpa bytes dan path: SourceLoadException', () async {
      expect(
        () => loadSourceText(PdfInput(name: 'x.csv')),
        throwsA(isA<SourceLoadException>()),
      );
    });
  });

  group('loadSourceText — window read (memory/perf)', () {
    test('file > maxChars: preview identik dengan truncate full-decode', () async {
      final big = List.filled(5000, 'é\n').join(); // multi-byte + baris pendek
      final path = await writeFile('big.csv', big);
      final r = await loadSourceText(
        PdfInput(name: 'big.csv', path: path, format: InputFormat.csv),
        maxChars: 100,
      );
      final full = truncateText(
        utf8.decode(await File(path).readAsBytes()),
        maxChars: 100,
      );
      expect(r.content, full.preview);
      expect(r.truncated, full.truncated);
      expect(r.content.contains('\uFFFD'), isFalse);
    });

    test('baris tanpa newline > maxChars: potong di maxChars tanpa artefak',
        () async {
      final longLine = 'x' * 20000; // tanpa '\n' sama sekali
      final path = await writeFile('long.csv', longLine);
      final r = await loadSourceText(
        PdfInput(name: 'long.csv', path: path, format: InputFormat.csv),
        maxChars: 100,
      );
      expect(r.truncated, isTrue);
      expect(r.content.length, 100);
      expect(r.content, 'x' * 100);
    });

    test('file multibyte (é) > maxChars: preview identik dengan full-decode',
        () async {
      // Regresi desain window: maxChars dihitung KARAKTER, window dalam BYTE —
      // tanpa faktor 4×, 'é\n' (3 byte/baris) membuat window decode ke <
      // maxChars karakter → preview lebih pendek dari full-decode.
      final big = List.filled(5000, 'é\n').join();
      final path = await writeFile('mb.csv', big);
      final r = await loadSourceText(
        PdfInput(name: 'mb.csv', path: path, format: InputFormat.csv),
        maxChars: 100,
      );
      final full = truncateText(
        utf8.decode(await File(path).readAsBytes()),
        maxChars: 100,
      );
      expect(r.content, full.preview);
      expect(r.truncated, full.truncated);
    });
  });

  group('loadSourcePdf', () {
    test('path: SourcePdf(path), bytes null', () async {
      final path = await writeFile('a.pdf', 'dummy');
      final r = await loadSourcePdf(
        PdfInput(name: 'a.pdf', path: path, format: InputFormat.pdf),
      );
      expect(r, isA<SourcePdf>());
      expect(r.path, path);
      expect(r.bytes, isNull);
    });

    test('bytes: SourcePdf(bytes), path null', () async {
      final pdf = buildTestPdf();
      final r = await loadSourcePdf(
        PdfInput(name: 'a.pdf', bytes: pdf, format: InputFormat.pdf),
      );
      expect(r.path, isNull);
      expect(r.bytes, same(pdf));
    });

    test('tanpa bytes dan path: SourceLoadException', () async {
      expect(
        () => loadSourcePdf(PdfInput(name: 'a.pdf')),
        throwsA(isA<SourceLoadException>()),
      );
    });
  });

  group('loadSource (routing)', () {
    test('csv → SourceText (teks mentah)', () async {
      final path = await writeFile('a.csv', 'a,b\n1,2\n');
      final r = await loadSource(
        PdfInput(name: 'a.csv', path: path, format: InputFormat.csv),
      );
      expect(r, isA<SourceText>());
      expect((r as SourceText).content, 'a,b\n1,2\n');
    });

    test('rtf → SourceText (teks mentah)', () async {
      final path = await writeFile('a.rtf', '{\\rtf1 Hello}');
      final r = await loadSource(
        PdfInput(name: 'a.rtf', path: path, format: InputFormat.rtf),
      );
      expect(r, isA<SourceText>());
    });

    test('format pdf → SourcePdf', () async {
      final r = await loadSource(
        PdfInput(
          name: 'a.pdf',
          bytes: buildTestPdf(),
          format: InputFormat.pdf,
        ),
      );
      expect(r, isA<SourcePdf>());
    });

    test('docx (zip) → SourceText via ZipTextPreview (tag di-strip)', () async {
      final docx = buildTestDocx(
        documentXml: docxDocument(
          '${docxParagraph(docxRun('Judul A'))}'
          '${docxParagraph(docxRun('Isi paragraf pertama.'))}',
        ),
      );
      final r = await loadSource(
        PdfInput(
          name: 'a.docx',
          bytes: docx,
          format: InputFormat.word,
        ),
      );
      expect(r, isA<SourceText>());
      expect((r as SourceText).content, contains('Judul A'));
      expect(r.content, contains('Isi paragraf pertama.'));
      expect(r.content, isNot(contains('<w:')));
    });

    test('epub (zip, entry XHTML) → SourceText via ZipTextPreview', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string(
          'OEBPS/ch1.xhtml',
          '<html><body><h1>Bab 1</h1><p>Teks.</p></body></html>',
        ));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      final r = await loadSource(
        PdfInput(name: 'a.epub', bytes: bytes, format: InputFormat.epub),
      );
      expect(r, isA<SourceText>());
      expect((r as SourceText).content, contains('Bab 1'));
      expect(r.content, isNot(contains('<h1')));
    });

    test('zip tanpa entry yang dikenal → SourceLoadException', () async {
      final archive = Archive()
        ..addFile(ArchiveFile.string('some/entry.txt', 'isi'));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      expect(
        () => loadSource(
          PdfInput(name: 'a.docx', bytes: bytes, format: InputFormat.word),
        ),
        throwsA(isA<SourceLoadException>()),
      );
    });

    test('format legacy (.doc) → SourceUnsupported', () async {
      expect(
        () => loadSource(
          PdfInput(name: 'a.doc', format: InputFormat.word),
        ),
        throwsA(isA<SourceUnsupportedException>()),
      );
    });

    test('format belum didukung preview (unknown) → SourceUnsupported',
        () async {
      for (final f in [InputFormat.unknown]) {
        expect(
          () => loadSource(PdfInput(name: 'a', format: f)),
          throwsA(isA<SourceUnsupportedException>()),
          reason: '$f harus ditolak',
        );
      }
    });
  });
}
