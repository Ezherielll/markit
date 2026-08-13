/// Internal pipeline layout model (pure Dart, no Flutter).
///
/// Coordinates: pure PDF coordinate system, origin bottom-left, Y upwards.
/// [TextSpan.yBottom] < [TextSpan.yTop] for normal text.
library;

import 'dart:math' as math;

/// A single text run (word/fragment) with absolute page position.
class TextSpan {
  TextSpan({
    required this.text,
    required this.xLeft,
    required this.xRight,
    required this.yBottom,
    required this.yTop,
    required this.fontSize,
  })  : assert(xLeft <= xRight),
        assert(yBottom <= yTop);

  final String text;
  final double xLeft;
  final double xRight;
  final double yBottom;
  final double yTop;

  /// Font size proxy (max character bbox height in fragment).
  final double fontSize;

  double get width => xRight - xLeft;
  double get height => yTop - yBottom;
  double get xCenter => (xLeft + xRight) / 2;
  double get yCenter => (yTop + yBottom) / 2;
}

/// Normalize PDFium fragment bounds: certain PDFs (glyph mirror/flipped,
/// rotated text) return left > right / bottom > top. Swapped to ensure
/// [TextSpan] invariants (xLeft <= xRight, yBottom <= yTop) are always satisfied —
/// defensive guard at boundary with external library (pdfrx).
({double xLeft, double xRight, double yBottom, double yTop})
    normalizeTextSpanBounds({
  required double left,
  required double right,
  required double bottom,
  required double top,
}) =>
    (
      xLeft: math.min(left, right),
      xRight: math.max(left, right),
      yBottom: math.min(bottom, top),
      yTop: math.max(bottom, top),
    );

/// A single text line: collection of [TextSpan]s sharing the same baseline.
class Line {
  Line({required this.spans}) : assert(spans.isNotEmpty);

  final List<TextSpan> spans;

  double get yTop => spans.map((s) => s.yTop).reduce(math.max);
  double get yBottom => spans.map((s) => s.yBottom).reduce(math.min);
  double get height => yTop - yBottom;
  double get yCenter => (yTop + yBottom) / 2;

  /// Representative font size of the line (maximum).
  double get fontSize => spans.map((s) => s.fontSize).reduce(math.max);

  /// Line text with word spacing normalization:
  /// if gap between fragments > 0.3 * fontSize, insert space.
  /// Small gaps or fragments with spaces are not duplicated.
  String get text {
    if (spans.length == 1) return spans.first.text;
    final buf = StringBuffer();
    for (var i = 0; i < spans.length; i++) {
      final s = spans[i];
      buf.write(s.text);
      if (i < spans.length - 1) {
        final next = spans[i + 1];
        final gap = next.xLeft - s.xRight;
        final threshold = s.fontSize * 0.3;
        if (gap > threshold && !s.text.endsWith(' ') && !next.text.startsWith(' ')) {
          buf.write(' ');
        }
      }
    }
    return buf.toString();
  }
}

/// Block types classified by the pipeline.
enum BlockType {
  heading,
  paragraph,
  listItem, // backward-compat alias
  unorderedListItem, // bullet item
  orderedListItem, // numbered item
  tableHeader, // first row of table → header + separator
  tableRow, // body row of table
}

/// Semantic block produced by classification, ready for markdown rendering.
class Block {
  Block({
    required this.type,
    required this.lines,
    this.headingLevel = 0,
    this.listDepth = 0,
    this.cells,
    this.listIndex,
    this.alignments,
  });

  final BlockType type;
  final List<String> lines;

  /// Heading level 1-based; 0 if not heading.
  final int headingLevel;

  /// Nested list depth (0=flat, 1=nested).
  final int listDepth;

  /// Table cells; non-null only for [BlockType.tableRow]/[BlockType.tableHeader].
  final List<String>? cells;

  /// Ordered list item number (1-based); null if not an ordered list.
  final int? listIndex;

  /// Table column alignments ('left'|'center'|'right'); null = all left.
  final List<String>? alignments;

  String get text => lines.join('\n');
}
