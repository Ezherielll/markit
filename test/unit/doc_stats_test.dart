import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/doc_stats.dart';
import 'package:markit/core/pdf_source.dart';
import 'package:markit/models/layout.dart';

/// Fake source: histogram sintetik tanpa file PDF.
class FakeSource implements PdfSource {
  FakeSource(this.pages);

  /// Tiap entry: daftar tinggi char (proxy fontSize) per halaman.
  /// Halaman dengan daftar kosong = halaman tanpa teks.
  final List<List<double>> pages;

  @override
  int get pageCount => pages.length;

  @override
  bool get isEncrypted => false;

  @override
  Future<LightPageData> loadLight(int pageIndex) async => LightPageData(
        pageIndex: pageIndex,
        charCount: pages[pageIndex].length,
        lineHeights: pages[pageIndex],
      );

  @override
  Future<List<TextSpan>> loadFull(int pageIndex) async => [];

  @override
  Future<void> dispose() async {}
}

void main() {
  group('DocStatsComputer', () {
    test('mode bucket = body font (FR-05, bukan hardcoded)', () async {
      // Body 12pt mendominasi (400 chars), heading 24pt & 18pt minor.
      final src = FakeSource([
        [...List.filled(200, 12.0), ...List.filled(10, 24.0)],
        [...List.filled(200, 12.0), ...List.filled(5, 18.0)],
      ]);
      final stats = await DocStatsComputer(src).compute();
      expect(stats.bodyFontSize, 12.0);
      expect(stats.emptyPages, 0);
      expect(stats.likelyScanned, isFalse);
    });

    test('empty pages counted; >=95% empty → likelyScanned (FR-10d)', () async {
      final src = FakeSource([
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [],
        [12.0, 12.0],
      ]);
      final stats = await DocStatsComputer(src).compute();
      expect(stats.emptyPages, 19);
      expect(stats.totalPages, 20);
      expect(stats.likelyScanned, isTrue);
      expect(stats.bodyFontSize, 12.0);
    });

    test('mixed: 2 empty dari 20 halaman → bukan scan', () async {
      final src = FakeSource([
        [],
        [],
        for (var i = 0; i < 18; i++) [12.0, 12.0, 12.0],
      ]);
      final stats = await DocStatsComputer(src).compute();
      expect(stats.likelyScanned, isFalse);
    });

    test('all empty → bodyFontSize 0, tidak crash', () async {
      final src = FakeSource([
        [],
        [],
      ]);
      final stats = await DocStatsComputer(src).compute();
      expect(stats.bodyFontSize, 0);
      expect(stats.likelyScanned, isTrue);
    });

    test('bucketing 0.5pt menyerap variasi glyph (11.7 vs 12.3)', () async {
      final src = FakeSource([
        [
          ...List.filled(100, 11.7),
          ...List.filled(100, 12.1),
          ...List.filled(100, 12.3),
          ...List.filled(6, 24.0),
        ],
      ]);
      final stats = await DocStatsComputer(src).compute();
      expect(stats.bodyFontSize, 12.0);
    });
  });
}
