import 'package:flutter_test/flutter_test.dart';
import 'package:markit/ui/widgets/markdown_helpers.dart';

void main() {
  group('truncateMarkdownPreview (bug #2 fix)', () {
    test('konten kecil: tidak dipotong', () {
      final r = truncateMarkdownPreview('# H1\n\nbody\n', maxChars: 1024);
      expect(r.truncated, isFalse);
      expect(r.preview, '# H1\n\nbody\n');
    });

    test('konten besar: dipotong di batas baris, bukan tengah', () {
      final big = List.filled(8000, '# Heading line\n').join();
      final r = truncateMarkdownPreview(big, maxChars: 64 * 1024);

      expect(r.truncated, isTrue);
      expect(r.preview.length, lessThan(big.length));
      // Potongan selalu berakhir dengan newline (batas baris).
      expect(r.preview.endsWith('\n'), isTrue);
      // Tidak ada baris terpotong di tengah.
      expect(r.preview.split('\n').every((l) => l.isEmpty || l.startsWith('# ')),
          isTrue);
    });

    test('baris sangat panjang (tanpa newline sebelum batas): potong di max',
        () {
      final longLine = 'x' * 2000;
      final r = truncateMarkdownPreview(longLine, maxChars: 1000);
      expect(r.truncated, isTrue);
      expect(r.preview.length, 1000);
    });

    test('konten asli tidak pernah dimodifikasi (untuk download)', () {
      final big = List.filled(8000, '# Heading line\n').join();
      truncateMarkdownPreview(big, maxChars: 64 * 1024);
      expect(big.length, 8000 * '# Heading line\n'.length);
    });
  });
}
