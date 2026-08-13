import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/source/source_loader.dart';

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
      final path = await writeFile('a.txt', 'halo\ndunia\n');
      final r = await loadSourceText(
        PdfInput(name: 'a.txt', path: path, format: InputFormat.text),
      );
      expect(r, isA<SourceText>());
      expect(r.content, 'halo\ndunia\n');
      expect(r.truncated, isFalse);
    });

    test('konten > maxChars: terpotong di batas baris', () async {
      final big = List.filled(8000, 'baris ke-N\n').join();
      final path = await writeFile('big.txt', big);
      final r = await loadSourceText(
        PdfInput(name: 'big.txt', path: path, format: InputFormat.text),
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
          name: 'a.md',
          bytes: Uint8List.fromList(utf8.encode('# Judul\n\nisi\n')),
          format: InputFormat.markdown,
        ),
      );
      expect(r.content, '# Judul\n\nisi\n');
      expect(r.truncated, isFalse);
    });

    test('bytes rusak (bukan UTF-8): tidak throw, allowMalformed', () async {
      final r = await loadSourceText(
        PdfInput(
          name: 'b.bin',
          bytes: Uint8List.fromList([0xFF, 0xFE, 0x00, 0x41, 0x61]),
          format: InputFormat.text,
        ),
      );
      expect(r, isA<SourceText>());
    });

    test('file tidak ada: SourceLoadException', () async {
      expect(
        () => loadSourceText(
          PdfInput(name: 'x.txt', path: '${tmp.path}/missing.txt'),
        ),
        throwsA(isA<SourceLoadException>()),
      );
    });

    test('tanpa bytes dan path: SourceLoadException', () async {
      expect(
        () => loadSourceText(PdfInput(name: 'x.txt')),
        throwsA(isA<SourceLoadException>()),
      );
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
    test('format teks → SourceText', () async {
      final path = await writeFile('a.csv', 'a,b\n1,2\n');
      final r = await loadSource(
        PdfInput(name: 'a.csv', path: path, format: InputFormat.csv),
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

    test('format belum didukung (docx/zip/unknown) → SourceUnsupported',
        () async {
      for (final f in [
        InputFormat.docx,
        InputFormat.xlsx,
        InputFormat.pptx,
        InputFormat.epub,
        InputFormat.zip,
        InputFormat.image,
        InputFormat.audio,
        InputFormat.unknown,
      ]) {
        expect(
          () => loadSource(PdfInput(name: 'a', format: f)),
          throwsA(isA<SourceUnsupportedException>()),
          reason: '$f harus ditolak',
        );
      }
    });
  });
}
