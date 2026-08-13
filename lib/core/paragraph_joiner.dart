import 'dart:math' as math;

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

    // BARU (Fase C): pre-pass untuk hiphenasi intra-halaman
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

  /// Pre-pass: gabungkan pasangan baris yang terhifen.
  /// Rule: baris A berakhir '-' DAN karakter pertama baris B adalah [a-z].
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
          // Gabungkan: hapus '-', gabung spans
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

  /// Buat Line baru dengan menggabungkan baris A (tanpa trailing '-') + baris B.
  Line _mergeHyphenated(Line a, Line b) {
    // Salin spans baris A, hapus '-' dari span terakhir
    final aSpans = a.spans.toList();
    if (aSpans.isNotEmpty && b.spans.isNotEmpty) {
      final last = aSpans.last;
      final trimmed = last.text.trimRight();
      if (trimmed.endsWith('-')) {
        aSpans[aSpans.length - 1] = TextSpan(
          text: trimmed.substring(0, trimmed.length - 1),
          // xRight diteruskan ke xLeft span pertama baris B sehingga gap X
          // antar-fragmen = 0 → Line.text tidak menyisipkan spasi
          // ("docu-" + "ment" → "document", bukan "docu ment").
          // Clamp: baris lanjutan yang dimulai lebih kiri (list wrap) membuat
          // xLeft baris B < xLeft baris A — tanpa max() assertion xLeft<=xRight
          // gagal di debug untuk list wrap yang ter-merge hiphenasi.
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
