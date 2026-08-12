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

  group('DocProfile multi-band heading (Fase A)', () {
    test('band clustering: heading bands sorted desc → H1, H2, H3', () {
      final profile = DocProfile.fromHistogram(
        {12.0: 100, 14.0: 4, 16.0: 3, 20.0: 2},
        totalPages: 2,
      );
      expect(profile.bodyFontSize, 12.0);
      expect(profile.headingBands, hasLength(3));
      expect(profile.headingBands[0].headingLevel, 1);
      expect(profile.headingBands[0].minSize, closeTo(20, 0.01));
      expect(profile.headingBands[1].headingLevel, 2);
      expect(profile.headingBands[1].minSize, closeTo(16, 0.01));
      expect(profile.headingBands[2].headingLevel, 3);
      expect(profile.headingBands[2].minSize, closeTo(14, 0.01));
    });

    test('bandForSize: body size → null; heading sizes → band yang tepat', () {
      final profile = DocProfile.fromHistogram(
        {12.0: 100, 14.0: 4, 16.0: 3, 20.0: 2},
        totalPages: 1,
      );
      expect(profile.bandForSize(12.0), isNull);
      expect(profile.bandForSize(13.0), isNull);
      expect(profile.bandForSize(14.0)?.headingLevel, 3);
      expect(profile.bandForSize(20.0)?.headingLevel, 1);
    });

    test('satu kemunculan ukuran besar → bukan heading band', () {
      final profile = DocProfile.fromHistogram(
        {12.0: 100, 30.0: 1},
        totalPages: 1,
      );
      expect(profile.headingBands, isEmpty);
      expect(profile.bandForSize(30.0), isNull);
    });

    test('ukuran dekat body (13 vs 12) → bukan heading band', () {
      final profile = DocProfile.fromHistogram(
        {12.0: 100, 13.0: 5},
        totalPages: 1,
      );
      expect(profile.headingBands, isEmpty);
    });

    test('clustering gap <= 1.5pt: variasi glyph menyatu dalam satu band', () {
      final profile = DocProfile.fromHistogram(
        {11.5: 50, 12.0: 50, 12.5: 20, 16.0: 3},
        totalPages: 1,
      );
      expect(profile.bodyFontSize, 12.0);
      expect(profile.headingBands, hasLength(1));
      expect(profile.headingBands.single.headingLevel, 1);
      expect(profile.headingBands.single.minSize, closeTo(16, 0.01));
    });

    test('computeProfile: histogram halaman mengalir ke DocProfile', () async {
      final src = FakeSource([
        [...List.filled(200, 12.0), ...List.filled(4, 14.0), ...List.filled(2, 20.0)],
        [...List.filled(200, 12.0), ...List.filled(3, 16.0)],
      ]);
      final profile = await DocStatsComputer(src).computeProfile();
      expect(profile.bodyFontSize, 12.0);
      expect(profile.headingBands, hasLength(3));
      expect(profile.headingBands[0].headingLevel, 1);
      expect(profile.headingBands[1].headingLevel, 2);
      expect(profile.headingBands[2].headingLevel, 3);
      expect(profile.totalPages, 2);
      expect(profile.emptyPages, 0);
      expect(profile.likelyScanned, isFalse);
    });
  });
}
