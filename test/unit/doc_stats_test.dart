import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/doc_stats.dart';
import 'package:markit/core/pdf_source.dart';
import 'package:markit/core/pdfrx_source.dart';
import 'package:markit/models/layout.dart';

import '../helpers/pdf_factory.dart';

/// Fake source: histogram sintetik tanpa file PDF.
class FakeSource implements PdfSource {
  FakeSource(this.pages, {this.fullPages = const []});

  /// Tiap entry: daftar tinggi char (proxy fontSize) per halaman.
  /// Halaman dengan daftar kosong = halaman tanpa teks.
  final List<List<double>> pages;

  /// Fase C: spans berposisi per halaman (untuk sampling xLeft).
  /// Kosong = tidak tersedia → loadFull mengembalikan daftar kosong.
  final List<List<TextSpan>> fullPages;

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
  Future<List<TextSpan>> loadFull(int pageIndex) async =>
      fullPages.isEmpty ? const [] : fullPages[pageIndex];

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

  group('DocProfile geometry fields (Fase B)', () {
    test('bodyLeftMargin adalah mode xLeft dari body-sized spans', () {
      // Histogram dengan body size 12pt; spans xLeft di 72 (dominan) dan 100
      final hist = {12.0: 100, 18.0: 10};
      final xLeftSamples = <double>[72, 72, 72, 72, 72, 100, 100, 72, 72, 100];
      final profile = DocProfile.fromHistogram(
        hist,
        totalPages: 3,
        pageWidths: [612, 612, 612],
        pageHeights: [792, 792, 792],
        bodyXLeftSamples: xLeftSamples,
      );
      expect(profile.pageWidth, closeTo(612, 1));
      expect(profile.pageHeight, closeTo(792, 1));
      expect(profile.bodyLeftMargin, closeTo(72, 5)); // mode dari samples
      // bodyRightMargin = pageWidth - bodyLeftMargin (simetris default)
      expect(profile.bodyRightMargin, closeTo(612 - 72, 10));
    });

    test('pageWidth/pageHeight adalah median dari semua halaman', () {
      final hist = {12.0: 100};
      final profile = DocProfile.fromHistogram(
        hist,
        totalPages: 3,
        pageWidths: [612, 612, 595], // A4 mixed dengan Letter
        pageHeights: [792, 792, 842],
        bodyXLeftSamples: [72.0],
      );
      expect(profile.pageWidth, closeTo(612, 1)); // median
      expect(profile.pageHeight, closeTo(792, 1)); // median
    });

    test('DocProfile menyimpan pageWidth/pageHeight dari PdfrxSource',
        () async {
      // PdfrxSource.openData() menghasilkan PDF 612x792 (US Letter dari pdf_factory)
      final src = await PdfrxSource.openData(buildTestPdf());
      final profile = await DocStatsComputer(src).computeProfile();
      await src.dispose();

      // PDF factory pakai MediaBox [0 0 612 792]
      expect(profile.pageWidth, closeTo(612, 5));
      expect(profile.pageHeight, closeTo(792, 5));
    });

    test('computeProfile: bodyLeftMargin = mode xLeft dari spans body-band',
        () async {
      // Halaman penuh: 3 spans body (xLeft 72) + 4 spans ukuran heading
      // (xLeft 150, fontSize 24) yang harus DIEKSKLUSI band filter
      // (12*1.1=13.2 < 24) — tanpa filter mode-nya 150, dengan filter 72.
      final src = FakeSource(
        [
          [...List.filled(200, 12.0)],
        ],
        fullPages: [
          [
            for (var i = 0; i < 3; i++)
              TextSpan(
                text: 'body',
                xLeft: 72,
                xRight: 90,
                yBottom: 0,
                yTop: 12,
                fontSize: 12,
              ),
            for (var i = 0; i < 4; i++)
              TextSpan(
                text: 'Heading',
                xLeft: 150,
                xRight: 200,
                yBottom: 0,
                yTop: 24,
                fontSize: 24,
              ),
          ],
        ],
      );
      final profile = await DocStatsComputer(src).computeProfile();
      expect(profile.bodyFontSize, 12.0);
      expect(profile.bodyLeftMargin, closeTo(72, 1)); // mode xLeft body-band
    });
  });

  group('PipelineConfig zona header/footer (Fase B)', () {
    test('default: headerZoneFraction=0.93, footerZoneFraction=0.08', () {
      const config = PipelineConfig();
      expect(config.headerZoneFraction, closeTo(0.93, 0.001));
      expect(config.footerZoneFraction, closeTo(0.08, 0.001));
    });

    test('override header/footer zone', () {
      const config = PipelineConfig(headerZoneFraction: 0.95, footerZoneFraction: 0.05);
      expect(config.headerZoneFraction, closeTo(0.95, 0.001));
      expect(config.footerZoneFraction, closeTo(0.05, 0.001));
    });
  });
}
