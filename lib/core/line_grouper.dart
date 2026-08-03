import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage 2: grouping fragment → baris (FR-03).
///
/// Strategi: sortir span top-to-bottom (y PDF ke atas), lalu cluster greedy
/// berdasarkan jarak yCenter relatif terhadap tinggi baris yang sedang dibangun.
/// Dalam satu baris, span diurutkan left-to-right.
class LineGrouper {
  LineGrouper({this.config = const PipelineConfig()});

  final PipelineConfig config;

  /// Koordinat PDF: y semakin besar = semakin atas halaman.
  List<Line> group(List<TextSpan> spans) {
    if (spans.isEmpty) return [];

    final sorted = [...spans]
      ..sort((a, b) => b.yCenter.compareTo(a.yCenter));

    final lines = <List<TextSpan>>[];
    for (final span in sorted) {
      if (lines.isEmpty) {
        lines.add([span]);
        continue;
      }
      final current = lines.last;
      final lineHeight = current.map((s) => s.height).reduce(
            (a, b) => a > b ? a : b,
          );
      final tolerance =
          (lineHeight > span.height ? lineHeight : span.height) *
              config.lineToleranceFactor;
      final lineY = _yCenter(current);
      if ((span.yCenter - lineY).abs() <= tolerance) {
        current.add(span);
      } else {
        lines.add([span]);
      }
    }

    final result = <Line>[];
    for (final spansInLine in lines) {
      spansInLine.sort((a, b) => a.xLeft.compareTo(b.xLeft));
      result.add(Line(spans: spansInLine));
    }
    return result;
  }

  double _yCenter(List<TextSpan> spans) {
    var top = spans.first.yTop;
    var bottom = spans.first.yBottom;
    for (final s in spans.skip(1)) {
      if (s.yTop > top) top = s.yTop;
      if (s.yBottom < bottom) bottom = s.yBottom;
    }
    return (top + bottom) / 2;
  }
}
