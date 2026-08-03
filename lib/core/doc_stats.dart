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
