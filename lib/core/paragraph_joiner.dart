import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage 3: penggabungan baris → paragraf (FR-04).
///
/// Batas paragraf: gap vertikal antar-baris > median gap × [PipelineConfig.paragraphGapFactor],
/// atau indent baris pertama. Heading selalu menjadi blok tersendiri.
class ParagraphJoiner {
  ParagraphJoiner({this.config = const PipelineConfig()});

  final PipelineConfig config;

  /// [lines] harus sudah terurut top-to-bottom (dari [LineGrouper]).
  /// [isHeading] callback dari classifier (baris heading memutus paragraf).
  List<List<Line>> join(List<Line> lines, {required bool Function(Line) isHeading}) {
    if (lines.isEmpty) return [];

    final gaps = <double>[];
    for (var i = 1; i < lines.length; i++) {
      gaps.add(_gapBetween(lines[i - 1], lines[i]));
    }
    final threshold = _splitThreshold(gaps, config.paragraphGapFactor);

    final paragraphs = <List<Line>>[];
    var current = <Line>[];

    void flush() {
      if (current.isNotEmpty) {
        paragraphs.add(current);
        current = [];
      }
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final isFirst = i == 0;
      final hasIndent = isFirst ? false : _hasFirstLineIndent(lines[i - 1], line);

      if (isFirst) {
        current = [line];
        continue;
      }

      final gap = _gapBetween(lines[i - 1], line);
      final breaksParagraph = gap > threshold;
      final startsWithHeading = isHeading(line);
      final prevIsHeading = isHeading(lines[i - 1]);

      if (breaksParagraph || hasIndent || startsWithHeading || prevIsHeading) {
        flush();
      }
      current.add(line);
    }
    flush();
    return paragraphs;
  }

  double _gapBetween(Line a, Line b) => a.yBottom - b.yTop;

  /// Indent baris pertama paragraf: xLeft baris ini > xLeft baris sebelumnya
  /// (dan sebelumnya bukan heading).
  bool _hasFirstLineIndent(Line prev, Line line) {
    return line.spans.isNotEmpty &&
        prev.spans.isNotEmpty &&
        line.spans.first.xLeft > prev.spans.first.xLeft + prev.fontSize * 0.5;
  }

  /// Threshold pemisah paragraf: median dari gap "normal" (di bawah median
  /// pertama) × faktor. Gap antar-paragraf (outlier besar) tidak ikut
  /// mencemari median — lihat test gap besar.
  static double _splitThreshold(List<double> gaps, double factor) {
    if (gaps.isEmpty) return double.infinity;
    final m1 = _median(gaps);
    final small = gaps.where((g) => g < m1).toList();
    final base = small.isEmpty ? m1 : _median(small);
    return base * factor;
  }

  static double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
