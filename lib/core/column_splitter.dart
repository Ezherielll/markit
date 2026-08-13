import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage: separates [TextSpan]s per page into columns
/// based on horizontal gap detection, then arranges columns in reading order.
///
/// Algorithm (gap-based):
/// 1. Sort spans (excluding whitespace-only) left-to-right.
/// 2. Greedy cluster with "running max xRight": span enters current cluster
///    as long as xLeft is `<= maxXR + [_gapThreshold]% pageWidth`. Measured gap
///    is inter-span distance (xRight → xLeft), not xLeft difference.
/// 3. 2 clusters = 2 columns; split at gap midpoint. More than 2 clusters →
///    fallback single-column (maximum 2 columns supported).
///
/// Confidence gate: gap < [_gapThreshold]% pageWidth → not a column.
class ColumnSplitter {
  const ColumnSplitter();

  /// Minimum gap width threshold between columns (8% pageWidth).
  static const _gapThreshold = 0.08;

  /// Separate [spans] into columns based on [profile].
  ///
  /// Returns list of [TextSpan]s per column (sorted top-to-bottom).
  /// Reading order: left column first, then right.
  List<List<TextSpan>> split(List<TextSpan> spans, DocProfile profile) {
    if (spans.isEmpty) return [];
    if (profile.pageWidth <= 0) return [spans]; // no geometry info

    final splitX = _detectColumnSplit(spans, profile.pageWidth);
    if (splitX == null) {
      // Single-column: return all spans as one column, top-to-bottom
      return [[...spans]..sort((a, b) => b.yCenter.compareTo(a.yCenter))];
    }

    // Separate left and right by splitX
    final leftSpans = <TextSpan>[];
    final rightSpans = <TextSpan>[];
    for (final span in spans) {
      if (span.xLeft < splitX) {
        leftSpans.add(span);
      } else {
        rightSpans.add(span);
      }
    }

    // Sort each top-to-bottom (higher PDF Y = top)
    leftSpans.sort((a, b) => b.yCenter.compareTo(a.yCenter));
    rightSpans.sort((a, b) => b.yCenter.compareTo(a.yCenter));

    // Reading order: left column first
    final result = <List<TextSpan>>[];
    if (leftSpans.isNotEmpty) result.add(leftSpans);
    if (rightSpans.isNotEmpty) result.add(rightSpans);
    return result;
  }

  /// Find horizontal split point. Returns null for single-column.
  double? _detectColumnSplit(List<TextSpan> spans, double pageWidth) {
    // Cluster left-to-right with running max xRight.
    // Whitespace-only spans ignored.
    final sorted = spans
        .where((s) => s.text.trim().isNotEmpty)
        .toList()
      ..sort((a, b) => a.xLeft.compareTo(b.xLeft));
    if (sorted.length < 2) return null;

    final gapThreshold = pageWidth * _gapThreshold;
    final clusters = <List<TextSpan>>[];
    var current = <TextSpan>[sorted.first];
    var maxXRight = sorted.first.xRight;
    for (final span in sorted.skip(1)) {
      if (span.xLeft > maxXRight + gapThreshold) {
        clusters.add(current);
        current = [span];
        maxXRight = span.xRight;
      } else {
        current.add(span);
        if (span.xRight > maxXRight) maxXRight = span.xRight;
      }
    }
    clusters.add(current);

    // Single-column / more than 2 columns (3+ columns → fallback)
    if (clusters.length != 2) return null;

    // Split at gap midpoint between left and right columns
    final leftEdge = clusters[0].last.xRight;
    final rightEdge = clusters[1].first.xLeft;
    return (leftEdge + rightEdge) / 2;
  }
}
