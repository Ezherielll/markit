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

  /// Toleransi center: sel dianggap center bila |cellCenter - colCenter| <=
  /// [centerTolerance] * lebar kolom.
  static const double centerTolerance = 0.15;

  /// Toleransi kiri: sel dianggap left bila cellLeft - colLeft <
  /// [leftTolerance] * lebar kolom (setelah lolos cek center).
  static const double leftTolerance = 0.25;

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

  /// Deteksi alignment per kolom dari posisi sel vs ekstent kolom.
  ///
  /// Batas kolom diambil dari EKSTENT SEL lintas semua baris (bukan gap
  /// center — gap center menghasilkan kolom asimetris yang membuat sel
  /// sempit tak pernah center):
  /// colLeft[c] = min xLeft sel kolom c lintas baris; colRight[c] = max xRight.
  /// Per sel: center bila SEL LEBIH SEMPIT dari 0.75*lebar kolom DAN
  /// |cellCenter - colCenter| <= [centerTolerance]*lebar kolom; else left
  /// bila menempel batas kiri ([leftTolerance]); else right bila menempel
  /// batas kanan; else center. Mayoritas suara lintas baris; tie → 'left'.
  List<String> computeAlignments(List<List<Line>> tableParas, List<double> splitXs) {
    if (splitXs.isEmpty || tableParas.isEmpty) return const [];

    final colCount = splitXs.length + 1;
    final colLefts = List.generate(colCount, (_) => double.infinity);
    final colRights = List.generate(colCount, (_) => double.negativeInfinity);
    final cellData = <(int col, double left, double right)>[];

    for (final para in tableParas) {
      if (para.isEmpty) continue;
      for (final span in para.first.spans) {
        final idx = _columnIndex(span, splitXs);
        if (span.xLeft < colLefts[idx]) colLefts[idx] = span.xLeft;
        if (span.xRight > colRights[idx]) colRights[idx] = span.xRight;
        cellData.add((idx, span.xLeft, span.xRight));
      }
    }

    final votes = List.generate(colCount, (_) => <String>[]);
    for (final (col, left, right) in cellData) {
      votes[col].add(_cellAlignment(left, right, colLefts[col], colRights[col]));
    }

    return [for (var c = 0; c < colCount; c++) _majority(votes[c])];
  }

  /// Indeks kolom sebuah span: posisi split pertama yang dilampaui xMid
  /// (konsisten dengan [extractCells]).
  static int _columnIndex(TextSpan span, List<double> splitXs) {
    final xMid = (span.xLeft + span.xRight) / 2;
    for (var i = 0; i < splitXs.length; i++) {
      if (xMid < splitXs[i]) return i;
    }
    return splitXs.length;
  }

  /// Suara alignment satu sel terhadap batas kolom lintas baris:
  /// center bila sel lebih sempit dari 0.75*lebar kolom DAN center sel
  /// dalam [centerTolerance]*lebar kolom dari center kolom; else left bila
  /// menempel batas kiri ([leftTolerance]); else right bila menempel batas
  /// kanan; else center.
  static String _cellAlignment(
      double left, double right, double colLeft, double colRight) {
    final colWidth = colRight - colLeft;
    if (colWidth <= 0) return 'left';
    final colCenter = (colLeft + colRight) / 2;
    final cellCenter = (left + right) / 2;
    final cellWidth = right - left;

    if (cellWidth < colWidth * 0.75 &&
        (cellCenter - colCenter).abs() <= colWidth * centerTolerance) {
      return 'center';
    }
    if (left - colLeft < colWidth * leftTolerance) return 'left';
    if (colRight - right < colWidth * leftTolerance) return 'right';
    return 'center';
  }

  /// Mayoritas suara alignment lintas baris; tie → 'left'.
  static String _majority(List<String> votes) {
    if (votes.isEmpty) return 'left';
    final counts = <String, int>{};
    for (final a in votes) {
      counts[a] = (counts[a] ?? 0) + 1;
    }
    return counts.entries
        .reduce((a, b) => a.value >= b.value ? a : b)
        .key;
  }

  static double _medianDouble(List<double> values) {
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
