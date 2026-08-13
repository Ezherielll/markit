import 'dart:math' as math;

import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage 3: joining lines → paragraphs.
///
/// Paragraph boundary: vertical line gap > median gap * [PipelineConfig.paragraphGapFactor],
/// or first line indent. Headings always form separate blocks.
class ParagraphJoiner {
  ParagraphJoiner({this.config = const PipelineConfig()});

  final PipelineConfig config;

  /// [lines] must be sorted top-to-bottom (from [LineGrouper]).
  /// [isHeading] callback from classifier (heading lines split paragraphs).
  List<List<Line>> join(List<Line> lines, {required bool Function(Line) isHeading}) {
    if (lines.isEmpty) return [];

    // Pre-pass for intra-page dehyphenation
    final processed = _deHyphenate(lines);

    final gaps = <double>[];
    for (var i = 1; i < processed.length; i++) {
      gaps.add(_gapBetween(processed[i - 1], processed[i]));
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

    for (var i = 0; i < processed.length; i++) {
      final line = processed[i];
      final isFirst = i == 0;
      final hasIndent = isFirst ? false : _hasFirstLineIndent(processed[i - 1], line);

      if (isFirst) {
        current = [line];
        continue;
      }

      final gap = _gapBetween(processed[i - 1], line);
      final breaksParagraph = gap > threshold;
      final startsWithHeading = isHeading(line);
      final prevIsHeading = isHeading(processed[i - 1]);

      if (breaksParagraph || hasIndent || startsWithHeading || prevIsHeading) {
        flush();
      }
      current.add(line);
    }
    flush();
    return paragraphs;
  }

  /// Pre-pass: join hyphenated line pairs.
  /// Rule: line A ends with '-' AND first character of line B is [a-z].
  List<Line> _deHyphenate(List<Line> lines) {
    if (lines.length < 2) return lines;

    final result = <Line>[];
    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final lineText = line.text.trimRight();

      if (i + 1 < lines.length &&
          lineText.endsWith('-') &&
          lineText.length > 1) {
        final nextText = lines[i + 1].text.trimLeft();
        if (nextText.isNotEmpty && RegExp(r'^[a-z]').hasMatch(nextText)) {
          // Merge: remove '-', join spans
          result.add(_mergeHyphenated(line, lines[i + 1]));
          i += 2;
          continue;
        }
      }

      result.add(line);
      i++;
    }
    return result;
  }

  /// Create new Line by merging line A (without trailing '-') + line B.
  Line _mergeHyphenated(Line a, Line b) {
    // Copy line A spans, remove '-' from last span
    final aSpans = a.spans.toList();
    if (aSpans.isNotEmpty && b.spans.isNotEmpty) {
      final last = aSpans.last;
      final trimmed = last.text.trimRight();
      if (trimmed.endsWith('-')) {
        aSpans[aSpans.length - 1] = TextSpan(
          text: trimmed.substring(0, trimmed.length - 1),
          // xRight passed to xLeft of first span of line B so X-gap
          // between fragments = 0 → Line.text inserts no space
          // ("docu-" + "ment" → "document", not "docu ment").
          // Clamp: continuation line starting further left (list wrap)
          // makes xLeft of line B < xLeft of line A — without max() assertion
          // xLeft<=xRight fails in debug for hyphen-merged list wraps.
          xLeft: last.xLeft,
          xRight: math.max(last.xLeft, b.spans.first.xLeft),
          yBottom: last.yBottom,
          yTop: last.yTop,
          fontSize: last.fontSize,
        );
      }
    }
    return Line(spans: [...aSpans, ...b.spans]);
  }

  double _gapBetween(Line a, Line b) => a.yBottom - b.yTop;

  /// First line paragraph indent: xLeft of this line > xLeft of previous line
  /// (and previous line is not a heading).
  bool _hasFirstLineIndent(Line prev, Line line) {
    return line.spans.isNotEmpty &&
        prev.spans.isNotEmpty &&
        line.spans.first.xLeft > prev.spans.first.xLeft + prev.fontSize * 0.5;
  }

  /// Paragraph split threshold: median of "normal" gaps (below first median)
  /// * factor. Large gap outliers do not contaminate median.
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
