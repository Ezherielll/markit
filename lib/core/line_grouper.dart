import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage 2: grouping fragments → lines.
///
/// Strategy: sort spans top-to-bottom (higher PDF Y = top), then greedy cluster
/// based on yCenter distance relative to line height being built.
/// Within a line, spans are sorted left-to-right.
class LineGrouper {
  LineGrouper({
    this.config = const PipelineConfig(),
    this.profile,
  });

  final PipelineConfig config;

  /// Pass 1 profile (optional, backward compatibility).
  final DocProfile? profile;

  /// PDF coordinates: larger Y = higher on page.
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
