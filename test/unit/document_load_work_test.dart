import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/ui/widgets/document_load_work.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_dlw_test');
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

  test('file besar: content penuh, preview terpotong, stats dihitung', () {
    // Paragraf dipisah baris kosong: MdStats menggabungkan baris teks
    // beruntun (tanpa baris kosong) menjadi SATU paragraf.
    final big = '# Judul\n\n${'paragraf lebih panjang\n\n' * 5000}';
    final path = '${tmp.path}/big.md';
    File(path).writeAsStringSync(big);

    final result = loadDocumentWork((path: path, maxChars: 1024));

    expect(result.content, big);
    expect(result.truncated, isTrue);
    expect(result.preview.length, lessThanOrEqualTo(1024));
    expect(result.stats.headings, 1);
    expect(result.stats.paragraphs, greaterThan(100));
  });

  test('file kecil: tidak terpotong', () {
    final path = '${tmp.path}/small.md';
    File(path).writeAsStringSync('# A\n\nB\n');

    final result = loadDocumentWork((path: path, maxChars: 1024));

    expect(result.truncated, isFalse);
    expect(result.content, '# A\n\nB\n');
    expect(result.stats.headings, 1);
  });

  test('file hilang: FileSystemException', () {
    expect(
      () => loadDocumentWork((path: '${tmp.path}/missing.md', maxChars: 1024)),
      throwsA(isA<FileSystemException>()),
    );
  });
}
