import 'pdf_source.dart';

/// Koefisien heuristik pipeline, disentralkan untuk tuning mudah
/// (nantinya jadi advanced settings — keputusan D9).
class PipelineConfig {
  const PipelineConfig({
    this.headingFontFactor = 1.2,
    this.paragraphGapFactor = 1.5,
    this.lineToleranceFactor = 0.6,
    this.headerZoneFraction = 0.93, // Fase B: yTop > pageHeight * 0.93 = header
    this.footerZoneFraction = 0.08, // Fase B: yTop < pageHeight * 0.08 = footer
  });

  /// Baris dengan fontSize >= body * [headingFontFactor] → heading (FR-05).
  final double headingFontFactor;

  /// Gap antar-baris > medianGap * [paragraphGapFactor] → batas paragraf (FR-04).
  final double paragraphGapFactor;

  /// Fragment digabung ke baris jika jarak y < lineHeight * [lineToleranceFactor] (FR-03).
  final double lineToleranceFactor;

  /// Fraksi tinggi halaman untuk zona header (Fase B).
  final double headerZoneFraction;

  /// Fraksi tinggi halaman untuk zona footer (Fase B).
  final double footerZoneFraction;
}

/// Statistik seluruh dokumen hasil pass 1 (histogram ringan).
class DocStats {
  DocStats({
    required this.bodyFontSize,
    required this.totalPages,
    required this.emptyPages,
  });

  /// Proxy fontSize "body text" = bucket paling sering (mode).
  /// Dasar klasifikasi heading (FR-05), bukan threshold hardcoded.
  final double bodyFontSize;

  final int totalPages;

  /// Jumlah halaman tanpa teks terdeteksi (indikasi scan, FR-10d).
  final int emptyPages;

  /// Halaman tanpa teks >= 95% total → kemungkinan besar PDF hasil scan.
  bool get likelyScanned => totalPages > 0 && emptyPages / totalPages >= 0.95;
}

/// Satu pita ukuran font yang diklasifikasikan sebagai heading level tertentu
/// (Fase A: multi-band heading detection).
class HeadingBand {
  const HeadingBand({
    required this.minSize,
    required this.maxSize,
    required this.headingLevel,
  });

  final double minSize;
  final double maxSize;

  /// Level heading 1-based (1 = terbesar).
  final int headingLevel;

  /// Toleransi pencocokan: nilai hidup (un-bucketed) bisa beda hingga satu
  /// bucket (0.5pt) dari batas band yang tersimpan sebagai bucket center.
  static const double tolerance = 0.5;

  bool contains(double size) =>
      size >= minSize - tolerance && size <= maxSize + tolerance;
}

/// Profil dokumen hasil pass 1 (Fase A): body font + pita heading + konteks.
///
/// Menggantikan [DocStats] sebagai output utama [DocStatsComputer] —
/// [DocStats] dipertahankan untuk backward compat sementara.
class DocProfile {
  const DocProfile({
    required this.bodyFontSize,
    required this.headingBands,
    required this.totalPages,
    required this.emptyPages,
    this.pageWidth = 0, // Fase B: lebar halaman (median, unit PDF)
    this.pageHeight = 0, // Fase B: tinggi halaman (median, unit PDF)
    this.bodyLeftMargin = 0, // Fase B: margin kiri body (mode xLeft)
    this.bodyRightMargin = 0, // Fase B: margin kanan body
  });

  /// Proxy fontSize "body text" = bucket paling sering (mode).
  final double bodyFontSize;

  /// Pita ukuran heading, sorted descending size (H1, H2, ...), max H4.
  final List<HeadingBand> headingBands;

  final int totalPages;

  /// Jumlah halaman tanpa teks terdeteksi (indikasi scan, FR-10d).
  final int emptyPages;

  /// Lebar halaman (median seluruh halaman) dalam unit PDF (Fase B).
  final double pageWidth;

  /// Tinggi halaman (median seluruh halaman) dalam unit PDF (Fase B).
  final double pageHeight;

  /// Margin kiri body text (mode xLeft spans body) (Fase B).
  final double bodyLeftMargin;

  /// Margin kanan body text (default: simetris dengan kiri) (Fase B).
  final double bodyRightMargin;

  /// Lebar konten utama (antara margin kiri dan kanan) (Fase B).
  double get bodyWidth => bodyRightMargin - bodyLeftMargin;

  /// Zona header: yTop > [pageHeight] * [fraction] dianggap header (Fase B).
  double headerZoneBottom(double fraction) => pageHeight * fraction;

  /// Zona footer: yTop < [pageHeight] * [fraction] dianggap footer (Fase B).
  double footerZoneTop(double fraction) => pageHeight * fraction;

  /// Halaman tanpa teks >= 95% total → kemungkinan besar PDF hasil scan.
  bool get likelyScanned => totalPages > 0 && emptyPages / totalPages >= 0.95;

  /// Band heading yang memuat [size]; null bila bukan ukuran heading.
  HeadingBand? bandForSize(double size) {
    for (final band in headingBands) {
      if (band.contains(size)) return band;
    }
    return null;
  }

  /// Bangun profil dari histogram tinggi char (bucket = [DocStatsComputer.bucketSize]).
  ///
  /// Algoritma (design spec §4.1):
  /// 1. Cluster bucket berurutan dengan gap <= 1.5pt → band.
  /// 2. Body band = band yang memuat mode.
  /// 3. Heading bands = band dengan min > body * 1.1 dan frekuensi >= 2.
  /// 4. Sort bands desc size → H1, H2, H3, ... (maksimal H4).
  /// Fase B: pageWidth/pageHeight (median) + bodyLeftMargin (mode xLeft).
  static DocProfile fromHistogram(
    Map<double, int> hist, {
    required int totalPages,
    int emptyPages = 0,
    List<double> pageWidths = const [],
    List<double> pageHeights = const [],
    List<double> bodyXLeftSamples = const [],
  }) {
    if (hist.isEmpty) {
      return DocProfile(
        bodyFontSize: 0,
        headingBands: const [],
        totalPages: totalPages,
        emptyPages: emptyPages,
        pageWidth: _median(pageWidths.isEmpty ? [0] : pageWidths),
        pageHeight: _median(pageHeights.isEmpty ? [0] : pageHeights),
        bodyLeftMargin: _modeDouble(bodyXLeftSamples),
        bodyRightMargin: 0,
      );
    }

    final bands = _clusterBands(hist);
    final body = DocStatsComputer._mode(hist);
    final bodyBand =
        bands.firstWhere((b) => b.contains(body), orElse: () => bands.first);

    final sorted = [...bands]..sort((a, b) => b.maxSize.compareTo(a.maxSize));
    final headingBands = _levelBands(sorted, body, bodyBand);

    final pw = _median(pageWidths.isEmpty ? [0] : pageWidths);
    final ph = _median(pageHeights.isEmpty ? [0] : pageHeights);
    final leftMargin = _modeDouble(bodyXLeftSamples);
    final rightMargin = pw > 0 ? pw - leftMargin : 0.0;

    return DocProfile(
      bodyFontSize: body,
      headingBands: headingBands,
      totalPages: totalPages,
      emptyPages: emptyPages,
      pageWidth: pw,
      pageHeight: ph,
      bodyLeftMargin: leftMargin,
      bodyRightMargin: rightMargin,
    );
  }
}

/// Petakan band terurut-desc ke level heading H1..H4 (maksimal 4 level).
///
/// Body band dilewati; band yang terlalu dekat dengan body (≤ 1.1×) atau
/// berfrekuensi < 2 dianggap noise, bukan heading.
List<HeadingBand> _levelBands(
  List<_FontBand> sorted,
  double bodySize,
  _FontBand bodyBand,
) {
  final headingBands = <HeadingBand>[];
  var level = 1;
  for (final band in sorted) {
    if (identical(band, bodyBand)) continue;
    if (band.minSize <= bodySize * 1.1) continue; // terlalu dekat dengan body
    if (band.count < 2) continue; // outlier sekali muncul
    headingBands.add(HeadingBand(
      minSize: band.minSize,
      maxSize: band.maxSize,
      headingLevel: level,
    ));
    level++;
    if (level > 4) break; // maksimal H4 dalam praktik
  }
  return headingBands;
}

/// Mode dari list nilai double (rounded ke 1pt).
double _modeDouble(List<double> values) {
  if (values.isEmpty) return 0;
  final freq = <int, int>{};
  for (final v in values) {
    final key = v.round();
    freq[key] = (freq[key] ?? 0) + 1;
  }
  return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key.toDouble();
}

/// Median dari list double.
double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Cluster bucket histogram berurutan: bucket dengan gap <= 1.5pt dianggap
/// satu band ukuran font yang sama (menyerap variasi glyph).
List<_FontBand> _clusterBands(Map<double, int> hist) {
  final buckets = hist.keys.toList()..sort();
  final bands = <_FontBand>[];
  var min = buckets.first;
  var max = buckets.first;
  var count = hist[buckets.first]!;
  for (var i = 1; i < buckets.length; i++) {
    final b = buckets[i];
    if (b - max <= 1.5) {
      max = b;
      count += hist[b]!;
    } else {
      bands.add(_FontBand(min, max, count));
      min = b;
      max = b;
      count = hist[b]!;
    }
  }
  bands.add(_FontBand(min, max, count));
  return bands;
}

class _FontBand {
  _FontBand(this.minSize, this.maxSize, this.count);

  final double minSize;
  final double maxSize;
  final int count;

  bool contains(double size) => size >= minSize && size <= maxSize;
}

/// Pass 1: bangun histogram tinggi char dari seluruh halaman tanpa
/// menyimpan layout lengkap (memory O(1) relatif terhadap halaman).
class DocStatsComputer {
  DocStatsComputer(this._source);

  final PdfSource _source;

  /// Ukuran bucket histogram (0.5pt). PDF real bervariasi per glyph,
  /// jadi mode dihitung pada bucket, bukan nilai presisi.
  static const double bucketSize = 0.5;

  Future<DocStats> compute() async {
    final hist = <double, int>{};
    var emptyPages = 0;

    for (var i = 0; i < _source.pageCount; i++) {
      final page = await _source.loadLight(i);
      if (!page.hasText) {
        emptyPages++;
        continue;
      }
      for (final h in page.lineHeights) {
        if (h <= 0) continue;
        final bucket = (h / bucketSize).round() * bucketSize;
        hist[bucket] = (hist[bucket] ?? 0) + 1;
      }
    }

    return DocStats(
      bodyFontSize: _mode(hist),
      totalPages: _source.pageCount,
      emptyPages: emptyPages,
    );
  }

  /// Pass 1 (Fase A): hitung [DocProfile] — body font + pita heading
  /// multi-level + info halaman. Same pass tunggal seperti [compute].
  Future<DocProfile> computeProfile() async {
    final hist = <double, int>{};
    var emptyPages = 0;
    final pageWidths = <double>[];
    final pageHeights = <double>[];
    var firstTextPage = -1;

    for (var i = 0; i < _source.pageCount; i++) {
      final page = await _source.loadLight(i);
      if (!page.hasText) {
        emptyPages++;
        continue;
      }
      if (firstTextPage < 0) firstTextPage = i;
      // Fase B: kumpulkan geometri halaman (media box)
      if (page.pageWidth > 0) pageWidths.add(page.pageWidth);
      if (page.pageHeight > 0) pageHeights.add(page.pageHeight);
      for (final h in page.lineHeights) {
        if (h <= 0) continue;
        final bucket = (h / bucketSize).round() * bucketSize;
        hist[bucket] = (hist[bucket] ?? 0) + 1;
      }
    }

    // Fase C: loadLight tidak mengekspos xLeft → ambil sampel xLeft dari
    // halaman pertama berisi teks via loadFull. Hanya span berukuran body
    // (band ±0.8x..1.1x bodyFontSize) yang disertakan; heading/caption
    // dieksklusikan agar mode xLeft tidak bergeser. Bila loadFull gagal,
    // sampel dikosongkan (bodyLeftMargin default 0 — perilaku Fase B).
    final bodyFontSize = _mode(hist);
    final bodyXLeftSamples = firstTextPage >= 0
        ? await _sampleBodyXLefts(firstTextPage, bodyFontSize)
        : const <double>[];

    return DocProfile.fromHistogram(
      hist,
      totalPages: _source.pageCount,
      emptyPages: emptyPages,
      pageWidths: pageWidths,
      pageHeights: pageHeights,
      bodyXLeftSamples: bodyXLeftSamples,
    );
  }

  /// Sampel xLeft span berukuran body (0.8×..1.1× [bodyFontSize]) dari
  /// halaman pertama berisi teks. Kosong bila gagal load atau ukuran tidak
  /// valid (margin default 0).
  Future<List<double>> _sampleBodyXLefts(
    int firstTextPage,
    double bodyFontSize,
  ) async {
    if (bodyFontSize <= 0) return const [];
    try {
      final spans = await _source.loadFull(firstTextPage);
      final samples = <double>[];
      for (final s in spans) {
        if (s.fontSize >= bodyFontSize * 0.8 &&
            s.fontSize <= bodyFontSize * 1.1) {
          samples.add(s.xLeft);
        }
      }
      return samples;
    } catch (_) {
      // skip sampling — margin default 0 (kompatibel behavior lama)
      return const [];
    }
  }

  /// Bucket dengan densitas tertinggi di window ±[bucketSize]
  /// (jumlah bucket kiri + tengah + kanan). Lebih robust dari mode murni:
  /// variasi glyph di sekitar body font (mis. 11.7/12.0/12.3) terakumulasi
  /// menjadi satu puncak. Tie → bucket terbesar (konservatif: heading
  /// tidak pernah jadi body).
  static double _mode(Map<double, int> hist) {
    if (hist.isEmpty) return 0;
    final buckets = hist.keys.toList()..sort();
    double best = 0;
    var bestScore = -1;
    for (final b in buckets) {
      var score = hist[b]!;
      score += hist[b - bucketSize] ?? 0;
      score += hist[b + bucketSize] ?? 0;
      if (score >= bestScore) {
        bestScore = score;
        best = b;
      }
    }
    return best;
  }
}
