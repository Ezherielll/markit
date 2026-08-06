import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

Uint8List _concat(List<int> a, String b) =>
    Uint8List.fromList([...a, ...utf8.encode(b)]);

void main() {
  group('detectFormat — magic bytes', () {
    test('PDF via %PDF magic, tanpa ekstensi', () {
      expect(
        detectFormat('book', Uint8List.fromList([0x25, 0x50, 0x44, 0x46, 0x2D])),
        InputFormat.pdf,
      );
    });

    test('ZIP-based docx via PK magic + konten word/', () {
      final zip = _concat(
        [0x50, 0x4B, 0x03, 0x04],
        '[Content_Types].xml word/document.xml',
      );
      expect(detectFormat('renamed.dat', zip), InputFormat.docx);
    });

    test('ZIP-based xlsx via PK + xl/', () {
      final zip = _concat([0x50, 0x4B, 0x03, 0x04], 'xl/worksheets/sheet1.xml');
      expect(detectFormat('renamed.bin', zip), InputFormat.xlsx);
    });

    test('ZIP-based pptx via PK + ppt/', () {
      final zip = _concat([0x50, 0x4B, 0x03, 0x04], 'ppt/slides/slide1.xml');
      expect(detectFormat('renamed.blob', zip), InputFormat.pptx);
    });

    test('EPUB via PK + mimetype entry', () {
      final zip = _concat(
        [0x50, 0x4B, 0x03, 0x04],
        'mimetypeapplication/epub+zip',
      );
      expect(detectFormat('book.bin', zip), InputFormat.epub);
    });

    test('ZIP polos via PK', () {
      final zip = _concat([0x50, 0x4B, 0x03, 0x04], 'some/entry.txt');
      expect(detectFormat('archive.zip', zip), InputFormat.zip);
    });

    test('JPEG magic', () {
      final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      expect(detectFormat('photo.dat', jpeg), InputFormat.image);
    });

    test('PNG magic', () {
      final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      expect(detectFormat('img.bin', png), InputFormat.image);
    });

    test('MP3 ID3 magic', () {
      final mp3 = Uint8List.fromList([0x49, 0x44, 0x33, 0x04, 0x00]);
      expect(detectFormat('song.dat', mp3), InputFormat.audio);
    });

    test('JSON via { setelah whitespace', () {
      expect(detectFormat('data', _bytes('  \n{ "a": 1 }')), InputFormat.json);
    });

    test('JSON via [ tanpa ekstensi', () {
      expect(detectFormat('list', _bytes('[1, 2, 3]')), InputFormat.json);
    });

    test('XML via <?xml', () {
      expect(
        detectFormat('doc', _bytes('<?xml version="1.0"?><root/>')),
        InputFormat.xml,
      );
    });

    test('HTML via <!DOCTYPE html', () {
      expect(
        detectFormat('page', _bytes('<!DOCTYPE html><html><body>hi</body></html>')),
        InputFormat.html,
      );
    });

    test('HTML via <html langsung', () {
      expect(
        detectFormat('page', _bytes('<html><body>hi</body></html>')),
        InputFormat.html,
      );
    });
  });

  group('detectFormat — ekstensi fallback', () {
    test('txt', () => expect(detectFormat('a.txt', _bytes('x')), InputFormat.text));
    test('md', () => expect(detectFormat('a.md', _bytes('# t')), InputFormat.markdown));
    test('markdown', () {
      expect(detectFormat('a.markdown', _bytes('x')), InputFormat.markdown);
    });
    test('csv', () => expect(detectFormat('a.csv', _bytes('a,b')), InputFormat.csv));
    test('json ekstensi walau isi aneh', () {
      expect(detectFormat('a.json', _bytes('not json')), InputFormat.json);
    });
    test('xml ekstensi', () {
      expect(detectFormat('a.xml', _bytes('plain')), InputFormat.xml);
    });
    test('html ekstensi', () {
      expect(detectFormat('a.html', _bytes('plain')), InputFormat.html);
    });
    test('unknown untuk ekstensi tak dikenal', () {
      expect(detectFormat('a.xyz', _bytes('x')), InputFormat.unknown);
    });
  });

  group('isUrlName', () {
    test('http URL', () => expect(isUrlName('https://youtu.be/x'), isTrue));
    test('www', () => expect(isUrlName('www.example.com'), isTrue));
    test('bukan URL', () => expect(isUrlName('book.pdf'), isFalse));
  });
}

