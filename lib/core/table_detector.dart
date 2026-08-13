import '../models/layout.dart';
import 'doc_stats.dart';

/// Tagged result type: paragraph group + table flag.
typedef TaggedGroup = (List<List<Line>> paragraphs, bool isTable);
typedef TaggedParagraphs = List<TaggedGroup>;

/// Stage 4: detects consecutive lines forming a table.
///
/// Algorithm:
/// 1. Each "paragraph" treated as a potential table row.
/// 2. Find run >= [minTableRows] consecutive rows with consistent X-gaps.
/// 3. Consistency: gap position variance < [maxGapVariancePt].
/// 4. If consistent → group marked isTable=true; else → false.
///
/// Output table: first row becomes header (BlockType.tableHeader),
/// subsequent rows become rows (BlockType.tableRow).
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

  /// Center tolerance: cell considered centered if |cellCenter - colCenter| <=
  /// [centerTolerance] * column width.
  static const double centerTolerance = 0.15;

  /// Left tolerance: cell considered left-aligned if cellLeft - colLeft <
  /// [leftTolerance] * column width (after passing center check).
  static const double leftTolerance = 0.25;

  /// Tag paragraphs: group into table / non-table groups.
  ///
  /// Table rows may be interrupted by at most ONE non-table paragraph.
  /// If detected: two separate table groups (each >= 2 rows,
  /// total >= [minTableRows], gap variance consistent across all rows),
  /// with interrupter paragraph between them. More than one interrupter,
  /// sub-group size < 2, or inconsistent variance → fallback to single-paragraph groups.
  TaggedParagraphs tag(List<List<Line>> paragraphs, DocProfile profile) {
    if (paragraphs.isEmpty) return [];

    final result = <TaggedGroup>[];
    var i = 0;

    while (i < paragraphs.length) {
      if (!_isTableRowShape(paragraphs[i])) {
        result.add(([paragraphs[i]], false));
        i++;
        continue;
      }

      // Continuous run
      final runEnd = _findTableRunEnd(paragraphs, i);
      if (runEnd - i >= minTableRows) {
        result.add((paragraphs.sublist(i, runEnd), true));
        i = runEnd;
        continue;
      }

      // Candidate with single interrupter
      final next = _tryInterruptedTable(paragraphs, i, result);
      if (next != null) {
        i = next;
        continue;
      }

      result.add(([paragraphs[i]], false));
      i++;
    }

    return result;
  }

  /// Try grouping from [start] as table with single interrupter.
  /// Returns index after candidate on success (groups added to [result]),
  /// or null if conditions not met.
  int? _tryInterruptedTable(
      List<List<Line>> paragraphs, int start, List<TaggedGroup> result) {
    final candidate = _collectTableCandidate(paragraphs, start);
    if (candidate == null) return null;
    final (rows, interrupter, end) = candidate;
    if (rows.length < minTableRows || !_gapsConsistent(rows)) return null;

    if (interrupter != null) {
      // Split at interrupter: row count before interrupter = interrupter index
      final leftCount =
          _rowsBeforeInterrupter(paragraphs, start, end, interrupter.single);
      if (leftCount < 2 || rows.length - leftCount < 2) return null;
      result.add((rows.sublist(0, leftCount), true));
      result.add((interrupter, false));
      result.add((rows.sublist(leftCount), true));
    } else {
      // Null interrupter with run >= minTableRows: handled above
      result.add((rows, true));
    }
    return end;
  }

  /// Number of table rows before [interrupter] in range [start..end).
  int _rowsBeforeInterrupter(
      List<List<Line>> paragraphs, int start, int end, List<Line> interrupter) {
    var count = 0;
    for (var k = start; k < end; k++) {
      if (identical(paragraphs[k], interrupter)) break;
      count++;
    }
    return count;
  }

  /// Line has table row shape: number of X-gaps within supported column range
  /// (minColumns-1 .. maxColumns-1).
  bool _isTableRowShape(List<Line> para) {
    final gaps = _detectGaps(para);
    return gaps.length >= minColumns - 1 && gaps.length <= maxColumns - 1;
  }

  /// Gap position variance across rows < [maxGapVariancePt] for each column.
  bool _gapsConsistent(List<List<Line>> rows) {
    final gapPositions = <int, List<double>>{};
    for (final para in rows) {
      final gaps = _detectGaps(para);
      if (gaps.length < minColumns - 1 || gaps.length > maxColumns - 1) {
        return false;
      }
      for (var k = 0; k < gaps.length; k++) {
        gapPositions.putIfAbsent(k, () => []).add(gaps[k]);
      }
    }
    for (final positions in gapPositions.values) {
      if (_variance(positions) >= maxGapVariancePt) return false;
    }
    return true;
  }

  /// Find end of continuous table run from [start].
  int _findTableRunEnd(List<List<Line>> paragraphs, int start) {
    var j = start;
    while (j < paragraphs.length && _isTableRowShape(paragraphs[j])) {
      j++;
    }
    final runLength = j - start;
    if (runLength < minTableRows) return j;
    if (!_gapsConsistent(paragraphs.sublist(start, j))) return start;
    return j;
  }

  /// Collect table row candidates from [start] (guaranteed table row),
  /// allowing at most ONE interrupter paragraph between rows.
  ///
  /// Return: (rows, interrupter, end) — `rows` contains table rows only,
  /// `interrupter` null if none, `end` = index after candidate.
  (List<List<Line>> rows, List<List<Line>>? interrupter, int end)?
      _collectTableCandidate(List<List<Line>> paragraphs, int start) {
    final rows = <List<Line>>[];
    List<List<Line>>? interrupter;
    var j = start;

    while (j < paragraphs.length) {
      final para = paragraphs[j];
      if (_isTableRowShape(para)) {
        rows.add(para);
      } else if (interrupter == null) {
        interrupter = [para];
      } else {
        break; // second interrupter → candidate ends
      }
      j++;
    }

    if (rows.isEmpty) return null;
    if (interrupter != null && identical(interrupter.single, paragraphs[j - 1])) {
      interrupter = null; // trailing interrupter → not an interruption
    }
    return (rows, interrupter, j);
  }

  /// Detect X-gap positions in a single line.
  /// Returns list of horizontal gap center points (column separators).
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

  /// Calculate variance of value list.
  static double _variance(List<double> values) {
    if (values.length < 2) return 0;
    final mean = values.reduce((a, b) => a + b) / values.length;
    final sqDiffs = values.map((v) => (v - mean) * (v - mean));
    return sqDiffs.reduce((a, b) => a + b) / values.length;
  }

  /// Calculate median X split positions across all table rows.
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

  /// Extract cells from a single table row based on X split positions.
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

  /// Detect per-column alignment from cell positions vs column extent.
  ///
  /// Column bounds derived from CELL EXTENTS across all rows:
  /// colLeft[c] = min xLeft of column c cells; colRight[c] = max xRight.
  /// Per cell: center if CELL IS NARROWER than 0.75*column width AND
  /// |cellCenter - colCenter| <= [centerTolerance]*column width; else left
  /// if touching left bound ([leftTolerance]); else right if touching
  /// right bound; else center. Majority vote across rows; tie → 'left'.
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

  /// Column index of a span: first split position exceeded by xMid.
  static int _columnIndex(TextSpan span, List<double> splitXs) {
    final xMid = (span.xLeft + span.xRight) / 2;
    for (var i = 0; i < splitXs.length; i++) {
      if (xMid < splitXs[i]) return i;
    }
    return splitXs.length;
  }

  /// Alignment vote for a single cell against column bounds.
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

  /// Majority vote for alignment across rows; tie → 'left'.
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
