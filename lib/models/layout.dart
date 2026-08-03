/// Model layout internal pipeline (pure Dart, tanpa Flutter).
///
/// Koordinat: sistem koordinat PDF murni, origin bottom-left, Y ke atas.
/// [TextSpan.yBottom] < [TextSpan.yTop] untuk teks normal.
library;

import 'dart:math' as math;

/// Satu run teks (kata/fragment) dengan posisi absolut di halaman.
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

  /// Proxy ukuran font (tinggi bbox char terbesar di fragment).
  /// pdfrx 2.x tidak mengekspos fontSize; lihat docs/spike-pdfrx.md.
  final double fontSize;

  double get width => xRight - xLeft;
  double get height => yTop - yBottom;
  double get xCenter => (xLeft + xRight) / 2;
  double get yCenter => (yTop + yBottom) / 2;
}

/// Satu baris teks: kumpulan [TextSpan] yang berada pada baseline yang sama.
class Line {
  Line({required this.spans}) : assert(spans.isNotEmpty);

  final List<TextSpan> spans;

  double get yTop => spans.map((s) => s.yTop).reduce(math.max);
  double get yBottom => spans.map((s) => s.yBottom).reduce(math.min);
  double get height => yTop - yBottom;
  double get yCenter => (yTop + yBottom) / 2;

  /// Ukuran font representatif baris (terbesar).
  double get fontSize => spans.map((s) => s.fontSize).reduce(math.max);

  /// Teks baris: gabungan teks span berurutan (span pdfrx sudah mengandung spasi).
  String get text => spans.map((s) => s.text).join();
}

/// Jenis blok yang diklasifikasikan oleh pipeline.
enum BlockType { heading, paragraph, listItem }

/// Blok semantik hasil klasifikasi, siap dirender ke markdown.
class Block {
  Block({
    required this.type,
    required this.lines,
    this.headingLevel = 0,
  });

  final BlockType type;
  final List<String> lines;

  /// Level heading 1-based; 0 bila bukan heading.
  final int headingLevel;

  String get text => lines.join('\n');
}
