import 'pdf_source.dart';

/// Centralized pipeline heuristic coefficients for easy tuning.
class PipelineConfig {
  const PipelineConfig({
    this.headingFontFactor = 1.2,
    this.paragraphGapFactor = 1.5,
    this.lineToleranceFactor = 0.6,
    this.headerZoneFraction = 0.93,
    this.footerZoneFraction = 0.08,
  });

  /// Lines with fontSize >= body * [headingFontFactor] → heading.
  final double headingFontFactor;

  /// Line gap > medianGap * [paragraphGapFactor] → paragraph boundary.
  final double paragraphGapFactor;

  /// Fragments joined into line if y-distance < lineHeight * [lineToleranceFactor].
  final double lineToleranceFactor;

  /// Page height fraction for header zone.
  final double headerZoneFraction;

  /// Page height fraction for footer zone.
  final double footerZoneFraction;
}

/// Document-wide statistics from pass 1 (lightweight histogram).
class DocStats {
  DocStats({
    required this.bodyFontSize,
    required this.totalPages,
    required this.emptyPages,
  });

  /// Proxy "body text" fontSize = most frequent bucket (mode).
  /// Basis for heading classification, not a hardcoded threshold.
  final double bodyFontSize;

  final int totalPages;

  /// Count of pages without detected text (scanned PDF indication).
  final int emptyPages;

  /// Pages without text >= 95% total → likely a scanned PDF.
  bool get likelyScanned => totalPages > 0 && emptyPages / totalPages >= 0.95;
}

/// A single font size band classified as a specific heading level.
class HeadingBand {
  const HeadingBand({
    required this.minSize,
    required this.maxSize,
    required this.headingLevel,
  });

  final double minSize;
  final double maxSize;

  /// 1-based heading level (1 = largest).
  final int headingLevel;

  /// Matching tolerance: un-bucketed values can differ by up to one bucket (0.5pt).
  static const double tolerance = 0.5;

  bool contains(double size) =>
      size >= minSize - tolerance && size <= maxSize + tolerance;
}

/// Document profile from pass 1: body font + heading bands + page context.
///
/// Replaces [DocStats] as primary output of [DocStatsComputer].
class DocProfile {
  const DocProfile({
    required this.bodyFontSize,
    required this.headingBands,
    required this.totalPages,
    required this.emptyPages,
    this.pageWidth = 0,
    this.pageHeight = 0,
    this.bodyLeftMargin = 0,
    this.bodyRightMargin = 0,
  });

  /// Proxy "body text" fontSize = most frequent bucket (mode).
  final double bodyFontSize;

  /// Heading font size bands, sorted descending (H1, H2, ...), max H4.
  final List<HeadingBand> headingBands;

  final int totalPages;

  /// Count of pages without detected text (scanned indication).
  final int emptyPages;

  /// Page width (median across pages) in PDF units.
  final double pageWidth;

  /// Page height (median across pages) in PDF units.
  final double pageHeight;

  /// Body text left margin (mode of body span xLeft).
  final double bodyLeftMargin;

  /// Body text right margin.
  final double bodyRightMargin;

  /// Main content width (between left and right margin).
  double get bodyWidth => bodyRightMargin - bodyLeftMargin;

  /// Header zone: yTop > [pageHeight] * [fraction] considered header.
  double headerZoneBottom(double fraction) => pageHeight * fraction;

  /// Footer zone: yTop < [pageHeight] * [fraction] considered footer.
  double footerZoneTop(double fraction) => pageHeight * fraction;

  /// Pages without text >= 95% total → likely a scanned PDF.
  bool get likelyScanned => totalPages > 0 && emptyPages / totalPages >= 0.95;

  /// Heading band containing [size]; null if not a heading size.
  HeadingBand? bandForSize(double size) {
    for (final band in headingBands) {
      if (band.contains(size)) return band;
    }
    return null;
  }

  /// Build profile from char height histogram (bucket = [DocStatsComputer.bucketSize]).
  ///
  /// Algorithm:
  /// 1. Cluster consecutive buckets with gap <= 1.5pt → band.
  /// 2. Body band = band containing mode.
  /// 3. Heading bands = bands with min > body * 1.1 and count >= 2.
  /// 4. Sort bands desc size → H1, H2, H3, ... (max H4).
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

/// Map descending-sorted bands to heading levels H1..H4 (max 4 levels).
///
/// Body band skipped; bands too close to body (<= 1.1x) or count < 2 considered noise.
List<HeadingBand> _levelBands(
  List<_FontBand> sorted,
  double bodySize,
  _FontBand bodyBand,
) {
  final headingBands = <HeadingBand>[];
  var level = 1;
  for (final band in sorted) {
    if (identical(band, bodyBand)) continue;
    if (band.minSize <= bodySize * 1.1) continue;
    if (band.count < 2) continue;
    headingBands.add(HeadingBand(
      minSize: band.minSize,
      maxSize: band.maxSize,
      headingLevel: level,
    ));
    level++;
    if (level > 4) break;
  }
  return headingBands;
}

/// Mode from double value list (rounded to 1pt).
double _modeDouble(List<double> values) {
  if (values.isEmpty) return 0;
  final freq = <int, int>{};
  for (final v in values) {
    final key = v.round();
    freq[key] = (freq[key] ?? 0) + 1;
  }
  return freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key.toDouble();
}

/// Median from double list.
double _median(List<double> values) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

/// Cluster consecutive histogram buckets: gap <= 1.5pt considered same font band.
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

/// Pass 1: build char height histogram from all pages without storing full layout.
class DocStatsComputer {
  DocStatsComputer(this._source);

  final PdfSource _source;

  /// Histogram bucket size (0.5pt). Real PDFs vary per glyph, mode is computed on buckets.
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

  /// Pass 1: compute [DocProfile] — body font + multi-level heading bands + page info.
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
      // Collect page geometry (media box)
      if (page.pageWidth > 0) pageWidths.add(page.pageWidth);
      if (page.pageHeight > 0) pageHeights.add(page.pageHeight);
      for (final h in page.lineHeights) {
        if (h <= 0) continue;
        final bucket = (h / bucketSize).round() * bucketSize;
        hist[bucket] = (hist[bucket] ?? 0) + 1;
      }
    }

    // Sample xLeft from first text-bearing page via loadFull.
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

  /// Sample xLeft of body-sized spans (0.8x..1.1x [bodyFontSize]) from first text page.
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
      // skip sampling — default margin 0
      return const [];
    }
  }

  /// Bucket with highest density in window +/- [bucketSize].
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
