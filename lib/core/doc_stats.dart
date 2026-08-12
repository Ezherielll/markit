import 'pdf_source.dart';

/// Koefisien heuristik pipeline, disentralkan untuk tuning mudah
/// (nantinya jadi advanced settings — keputusan D9).
class PipelineConfig {
  const PipelineConfig({
    this.headingFontFactor = 1.2,
    this.paragraphGapFactor = 1.5,
    this.lineToleranceFactor = 0.6,
  });

  /// Baris dengan fontSize >= body * [headingFontFactor] → heading (FR-05).
  final double headingFontFactor;

  /// Gap antar-baris > medianGap * [paragraphGapFactor] → batas paragraf (FR-04).
  final double paragraphGapFactor;

  /// Fragment digabung ke baris jika jarak y < lineHeight * [lineToleranceFactor] (FR-03).
  final double lineToleranceFactor;
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
  });

  /// Proxy fontSize "body text" = bucket paling sering (mode).
  final double bodyFontSize;

  /// Pita ukuran heading, sorted descending size (H1, H2, ...), max H4.
  final List<HeadingBand> headingBands;

  final int totalPages;

  /// Jumlah halaman tanpa teks terdeteksi (indikasi scan, FR-10d).
  final int emptyPages;

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
  static DocProfile fromHistogram(
    Map<double, int> hist, {
    required int totalPages,
    int emptyPages = 0,
  }) {
    if (hist.isEmpty) {
      return DocProfile(
        bodyFontSize: 0,
        headingBands: const [],
        totalPages: totalPages,
        emptyPages: emptyPages,
      );
    }

    final bands = _clusterBands(hist);
    final body = DocStatsComputer._mode(hist);
    final bodyBand =
        bands.firstWhere((b) => b.contains(body), orElse: () => bands.first);

    final headingBands = <HeadingBand>[];
    final sorted = [...bands]..sort((a, b) => b.maxSize.compareTo(a.maxSize));
    var level = 1;
    for (final band in sorted) {
      if (identical(band, bodyBand)) continue;
      if (band.minSize <= body * 1.1) continue; // terlalu dekat dengan body
      if (band.count < 2) continue; // outlier sekali muncul
      headingBands.add(HeadingBand(
        minSize: band.minSize,
        maxSize: band.maxSize,
        headingLevel: level,
      ));
      level++;
      if (level > 4) break; // maksimal H4 dalam praktik
    }

    return DocProfile(
      bodyFontSize: body,
      headingBands: headingBands,
      totalPages: totalPages,
      emptyPages: emptyPages,
    );
  }
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

    return DocProfile.fromHistogram(
      hist,
      totalPages: _source.pageCount,
      emptyPages: emptyPages,
    );
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
