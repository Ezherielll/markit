import '../models/layout.dart';
import 'doc_stats.dart';

/// Tipe hasil tag: grup paragraf + flag apakah tabel.
typedef TaggedGroup = (List<List<Line>> paragraphs, bool isTable);
typedef TaggedParagraphs = List<TaggedGroup>;

/// Stage baru (Fase C): mendeteksi baris-baris berturut-turut yang membentuk tabel.
///
/// Algoritma:
/// 1. Tiap "paragraf" diperlakukan sebagai satu baris potensial tabel.
/// 2. Cari run >= [minTableRows] berturut-turut dengan X-gaps konsisten.
/// 3. Konsistensi: variance posisi gap antar-kolom < [maxGapVariancePt].
/// 4. Jika konsisten → grup ditandai isTable=true; jika tidak → false.
///
/// Tabel output: baris pertama jadi header (BlockType.tableHeader),
/// baris berikutnya jadi row (BlockType.tableRow).
class TableDetector {
  const TableDetector({
    this.minTableRows = 3,
    this.minColumns = 2,
    this.maxColumns = 8,
    this.gapThresholdPt = 20.0,
    this.maxGapVariancePt = 20.0,
  });

  final int minTableRows;
  final int minColumns;
  final int maxColumns;
  final double gapThresholdPt;
  final double maxGapVariancePt;

  /// Tag paragraphs: kelompokkan ke dalam grup tabel / bukan tabel.
  TaggedParagraphs tag(List<List<Line>> paragraphs, DocProfile profile) {
    if (paragraphs.isEmpty) return [];

    final result = <TaggedGroup>[];
    var i = 0;

    while (i < paragraphs.length) {
      final runEnd = _findTableRunEnd(paragraphs, i);
      final runLength = runEnd - i;

      if (runLength >= minTableRows) {
        result.add((paragraphs.sublist(i, runEnd), true));
        i = runEnd;
      } else {
        result.add(([paragraphs[i]], false));
        i++;
      }
    }

    return result;
  }

  /// Cari akhir run tabel dari indeks [start].
  int _findTableRunEnd(List<List<Line>> paragraphs, int start) {
    final gapPositions = <int, List<double>>{};

    var j = start;
    while (j < paragraphs.length) {
      final gaps = _detectGaps(paragraphs[j]);
      if (gaps.length < minColumns - 1 || gaps.length > maxColumns - 1) {
        break;
      }

      for (var k = 0; k < gaps.length; k++) {
        gapPositions.putIfAbsent(k, () => []).add(gaps[k]);
      }
      j++;
    }

    final runLength = j - start;
    if (runLength < minTableRows) return j;

    // Cek konsistensi: variance setiap posisi gap harus < maxGapVariancePt
    for (final positions in gapPositions.values) {
      if (_variance(positions) >= maxGapVariancePt) {
        return start; // variance terlalu besar → tidak ada tabel
      }
    }

    return j;
  }

  /// Deteksi posisi X-gap dalam satu baris.
  /// Return: list titik tengah gap horizontal (pemisah antar-kolom).
  List<double> _detectGaps(List<Line> para) {
    if (para.isEmpty) return [];
    final line = para.first;
    if (line.spans.length < 2) return [];

    final sorted = [...line.spans]..sort((a, b) => a.xLeft.compareTo(b.xLeft));

    final gaps = <double>[];
    for (var i = 0; i < sorted.length - 1; i++) {
      final gap = sorted[i + 1].xLeft - sorted[i].xRight;
      if (gap > gapThresholdPt) {
        gaps.add(sorted[i].xRight + gap / 2);
      }
    }
    return gaps;
  }

  /// Hitung variance dari list nilai.
  static double _variance(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sqDiffs = values.map((v) => (v - mean) * (v - mean));
    return sqDiffs.reduce((a, b) => a + b) / values.length;
  }

  /// Hitung posisi split X dari seluruh baris tabel menggunakan median per kolom.
  List<double> computeMedianSplitXs(List<List<Line>> tableParas) {
    if (tableParas.isEmpty) return [];

    final allGaps = <List<double>>[];
    for (final para in tableParas) {
      if (para.isNotEmpty) {
        allGaps.add(_detectGaps(para));
      }
    }

    if (allGaps.isEmpty) return [];

    final maxGaps = allGaps.map((g) => g.length).reduce((a, b) => a > b ? a : b);
    if (maxGaps == 0) return [];

    final result = <double>[];
    for (var k = 0; k < maxGaps; k++) {
      final positions = allGaps
          .where((gaps) => k < gaps.length)
          .map((gaps) => gaps[k])
          .toList();
      if (positions.isNotEmpty) {
        result.add(_medianDouble(positions));
      }
    }
    return result;
  }

  /// Ekstrak sel dari satu baris tabel berdasarkan posisi split X.
  List<String> extractCells(Line line, List<double> splitXs) {
    if (splitXs.isEmpty) {
      return [line.text.trim()];
    }

    final cells = List.generate(splitXs.length + 1, (_) => StringBuffer());
    for (final span in line.spans) {
      final xMid = (span.xLeft + span.xRight) / 2;
      var cellIdx = splitXs.length;
      for (var i = 0; i < splitXs.length; i++) {
        if (xMid < splitXs[i]) {
          cellIdx = i;
          break;
        }
      }
      if (cells[cellIdx].isNotEmpty) cells[cellIdx].write(' ');
      cells[cellIdx].write(span.text.trim());
    }

    return cells.map((c) => c.toString().trim()).toList();
  }

  static double _medianDouble(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
