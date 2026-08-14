import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/extractors/extractor_registry.dart';
import 'package:markit/core/format_catalog.dart';
import 'package:markit/core/input_format.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// ZIP sintetis berisi entry-entry dengan nama yang diberikan.
Uint8List _zip(List<String> entries) {
  final archive = Archive();
  for (final e in entries) {
    archive.addFile(ArchiveFile.string(e, '<x/>'));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const List<int> _ole2 = [0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1];

void main() {
  group('detectFormat — magic bytes', () {
    test('PDF via %PDF, tanpa ekstensi', () {
      expect(
        detectFormat('book', Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D])),
        InputFormat.pdf,
      );
    });

    test('RTF via {\\rtf', () {
      expect(
        detectFormat('doc.bin', _bytes('{\\rtf1\\ansi Hello')),
        InputFormat.rtf,
      );
    });

    test('ZIP docx (word/) walau di-rename', () {
      expect(
        detectFormat('renamed.dat', _zip(['[Content_Types].xml', 'word/document.xml'])),
        InputFormat.word,
      );
    });

    test('ZIP xlsx (xl/) walau di-rename', () {
      expect(
        detectFormat('renamed.bin', _zip(['xl/worksheets/sheet1.xml'])),
        InputFormat.excel,
      );
    });

    test('ZIP pptx (ppt/) walau di-rename', () {
      expect(
        detectFormat('renamed.blob', _zip(['ppt/slides/slide1.xml'])),
        InputFormat.powerpoint,
      );
    });

    test('ZIP opendocument (content.xml + mimetype) walau di-rename', () {
      expect(
        detectFormat('renamed.odt', _zip(['mimetype', 'content.xml'])),
        InputFormat.opendocument,
      );
    });

    test('ZIP epub (mimetype application/epub+zip)', () {
      expect(
        detectFormat('book.bin', _zip(['mimetype', 'META-INF/container.xml'])),
        InputFormat.epub,
      );
    });

    test('ZIP polos tanpa entry dikenal → unknown (format zip dihapus)', () {
      expect(
        detectFormat('archive.zip', _zip(['some/entry.txt'])),
        InputFormat.unknown,
      );
    });

    test('OLE2 magic + .doc → word', () {
      expect(
        detectFormat('old.doc', Uint8List.fromList([..._ole2, 0, 0])),
        InputFormat.word,
      );
    });

    test('OLE2 magic + .ppt → powerpoint', () {
      expect(
        detectFormat('old.ppt', Uint8List.fromList([..._ole2, 0, 0])),
        InputFormat.powerpoint,
      );
    });

    test('OLE2 magic + .xls → excel', () {
      expect(
        detectFormat('old.xls', Uint8List.fromList([..._ole2, 0, 0])),
        InputFormat.excel,
      );
    });

    test('OLE2 tanpa ekstensi dikenal → unknown', () {
      expect(
        detectFormat('mystery.bin', Uint8List.fromList([..._ole2, 0, 0])),
        InputFormat.unknown,
      );
    });
  });

  group('detectFormat — ekstensi fallback', () {
    test('semua ekstensi katalog → keluarga masing-masing', () {
      for (final family in kFormatCatalog) {
        for (final ext in family.extensions) {
          expect(detectFormat('file.$ext', _bytes('x')), family.format,
              reason: ext);
        }
      }
    });

    test('format yang dihapus (txt/md/json/xml/html/zip/image/audio) → unknown',
        () {
      for (final name in [
        'a.txt', 'a.md', 'a.markdown', 'a.json', 'a.xml', 'a.html', 'a.htm',
        'a.zip', 'a.jpg', 'a.png', 'a.gif', 'a.webp', 'a.wav', 'a.mp3',
        'a.flac', 'a.ogg',
      ]) {
        expect(detectFormat(name, _bytes('x')), InputFormat.unknown,
            reason: name);
      }
    });

    test('magic JSON/HTML lama tidak lagi dikenali', () {
      expect(detectFormat('data', _bytes('  \n{ "a": 1 }')), InputFormat.unknown);
      expect(detectFormat('list', _bytes('[1, 2, 3]')), InputFormat.unknown);
      expect(
        detectFormat('page', _bytes('<html><body>hi</body></html>')),
        InputFormat.unknown,
      );
    });

    test('unknown untuk ekstensi tak dikenal', () {
      expect(detectFormat('a.xyz', _bytes('x')), InputFormat.unknown);
    });

    test('nama tanpa titik sebelum ekstensi → unknown (regresi .ext)', () {
      for (final name in ['mypdf', 'datacsv', 'docx', 'a.txtcsv', 'indexhtml']) {
        expect(detectFormat(name, _bytes('x')), InputFormat.unknown,
            reason: name);
      }
    });
  });

  group('kDetectableExtensions (filter picker)', () {
    test('persis daftar ekstensi katalog (21)', () {
      final expected = [
        for (final f in kFormatCatalog) ...f.extensions,
      ];
      expect(kDetectableExtensions, expected);
      expect(kDetectableExtensions.length, 21);
    });

    test('tidak ada duplikat', () {
      expect(kDetectableExtensions.toSet().length, kDetectableExtensions.length);
    });
  });

  group('isUrlName', () {
    test('http URL', () => expect(isUrlName('https://youtu.be/x'), isTrue));
    test('www', () => expect(isUrlName('www.example.com'), isTrue));
    test('bukan URL', () => expect(isUrlName('book.pdf'), isFalse));
  });

  group('isFormatSupported & isLegacyFormatExtension', () {
    test('pdf/word/csv didukung konversi; sisanya roadmap', () {
      expect(isFormatSupported(InputFormat.pdf), isTrue);
      expect(isFormatSupported(InputFormat.word), isTrue);
      expect(isFormatSupported(InputFormat.csv), isTrue);
      expect(isFormatSupported(InputFormat.rtf), isTrue);
      expect(isFormatSupported(InputFormat.opendocument), isTrue);
      expect(isFormatSupported(InputFormat.powerpoint), isTrue);
      expect(isFormatSupported(InputFormat.excel), isFalse);
      expect(isFormatSupported(InputFormat.epub), isFalse);
    });

    test('legacy extension per keluarga (OLE2)', () {
      expect(isLegacyFormatExtension(InputFormat.word, 'a.doc'), isTrue);
      expect(isLegacyFormatExtension(InputFormat.word, 'a.docx'), isFalse);
      expect(isLegacyFormatExtension(InputFormat.word, 'a.docm'), isFalse);
      expect(isLegacyFormatExtension(InputFormat.powerpoint, 'a.ppt'), isTrue);
      expect(isLegacyFormatExtension(InputFormat.powerpoint, 'a.pps'), isTrue);
      expect(isLegacyFormatExtension(InputFormat.powerpoint, 'a.pot'), isTrue);
      expect(isLegacyFormatExtension(InputFormat.powerpoint, 'a.pptx'), isFalse);
      expect(isLegacyFormatExtension(InputFormat.excel, 'a.xls'), isTrue);
      expect(isLegacyFormatExtension(InputFormat.excel, 'a.xlsb'), isTrue);
      expect(isLegacyFormatExtension(InputFormat.excel, 'a.xlsx'), isFalse);
      expect(isLegacyFormatExtension(InputFormat.csv, 'a.csv'), isFalse);
    });

    test('registry: word → DocxExtractor, csv → CsvExtractor, rtf → RtfExtractor, opendocument → OdfExtractor, others null',
        () {
      expect(ExtractorRegistry.forFormat(InputFormat.word), isNotNull);
      expect(ExtractorRegistry.forFormat(InputFormat.csv), isNotNull);
      expect(ExtractorRegistry.forFormat(InputFormat.rtf), isNotNull);
      expect(ExtractorRegistry.forFormat(InputFormat.opendocument), isNotNull);
      expect(ExtractorRegistry.forFormat(InputFormat.powerpoint), isNotNull);
      expect(ExtractorRegistry.forFormat(InputFormat.excel), isNull);
      expect(ExtractorRegistry.forFormat(InputFormat.epub), isNull);
    });
  });
}
