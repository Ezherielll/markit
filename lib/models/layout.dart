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

  /// Teks baris dengan word spacing normalization (Fase B):
  /// jika gap antar fragment > 0.3 * fontSize, tambahkan spasi.
  /// Gap kecil / teks yang sudah mengandung spasi tidak digandakan.
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

/// Jenis blok yang diklasifikasikan oleh pipeline.
enum BlockType {
  heading,
  paragraph,
  listItem, // alias backward-compat
  unorderedListItem, // Fase A: item bullet
  orderedListItem, // Fase A: item bernomor
  tableHeader, // Fase C: baris pertama tabel → header + separator
  tableRow, // Fase C: baris isi tabel
}

/// Blok semantik hasil klasifikasi, siap dirender ke markdown.
class Block {
  Block({
    required this.type,
    required this.lines,
    this.headingLevel = 0,
    this.listDepth = 0, // Fase C: kedalaman nested list (0=flat, 1=nested)
    this.cells, // Fase C: sel tabel (non-null hanya untuk tableRow/tableHeader)
    this.listIndex, // Fase A: nomor ordered list (1-based); null untuk bullet
    this.alignments, // Fase D: 'left'|'center'|'right' per kolom; null = left
  });

  final BlockType type;
  final List<String> lines;

  /// Level heading 1-based; 0 bila bukan heading.
  final int headingLevel;

  /// Kedalaman nested list (0=flat, 1=nested).
  final int listDepth;

  /// Sel tabel; non-null hanya untuk [BlockType.tableRow]/[BlockType.tableHeader].
  final List<String>? cells;

  /// Nomor ordered list item (1-based); null bila bukan ordered list.
  final int? listIndex;

  /// Alignment per kolom tabel ('left'|'center'|'right'); null = semua left.
  final List<String>? alignments;

  String get text => lines.join('\n');
}
