import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage baru (Fase B): memisahkan [TextSpan] per halaman ke kolom-kolom
/// berdasarkan deteksi gap horizontal, lalu menyusun kolom dalam reading order.
///
/// Algoritma (design spec §4.2 — gap-based, bukan histogram xLeft):
/// 1. Sortir spans (tanpa whitespace-only) left-to-right.
/// 2. Cluster greedy dengan "running max xRight": span masuk cluster saat ini
///    selama xLeft-nya `<= maxXR + [_gapThreshold]% pageWidth`. Gap yang diukur
///    adalah jarak antar-span (xRight → xLeft), bukan selisih xLeft —
///    selisih xLeft antar kata panjang bisa besar walau teks bersambung.
/// 3. 2 cluster = 2 kolom; split di titik tengah gap. Lebih dari 2 cluster →
///    fallback single-column (maksimum 2 kolom didukung).
///
/// Confidence gate: gap < [_gapThreshold]% pageWidth → bukan kolom.
class ColumnSplitter {
  const ColumnSplitter();

  /// Threshold minimum lebar gap antar-kolom (8% pageWidth).
  /// Gabungan gap threshold + confidence gate dari design spec (5% + 8%)
  /// — 8% terbukti membedakan gap kata (<= 60pt) dari gap kolom (>= 120pt)
  /// pada halaman 612pt dengan teks 12pt.
  static const _gapThreshold = 0.08;

  /// Pisahkan [spans] ke kolom-kolom berdasarkan [profile].
  ///
  /// Return: list berisi daftar [TextSpan] per kolom (sudah diurutkan
  /// top-to-bottom). Reading order: kolom kiri dahulu, lalu kanan.
  List<List<TextSpan>> split(List<TextSpan> spans, DocProfile profile) {
    if (spans.isEmpty) return [];
    if (profile.pageWidth <= 0) return [spans]; // tidak ada info geometry

    final splitX = _detectColumnSplit(spans, profile.pageWidth);
    if (splitX == null) {
      // Single-column: return semua spans sebagai satu kolom, top-to-bottom
      return [[...spans]..sort((a, b) => b.yCenter.compareTo(a.yCenter))];
    }

    // Pisahkan ke kiri dan kanan berdasarkan splitX
    final leftSpans = <TextSpan>[];
    final rightSpans = <TextSpan>[];
    for (final span in spans) {
      if (span.xLeft < splitX) {
        leftSpans.add(span);
      } else {
        rightSpans.add(span);
      }
    }

    // Urutkan masing-masing top-to-bottom (y PDF besar = atas)
    leftSpans.sort((a, b) => b.yCenter.compareTo(a.yCenter));
    rightSpans.sort((a, b) => b.yCenter.compareTo(a.yCenter));

    // Reading order: kolom kiri dahulu
    final result = <List<TextSpan>>[];
    if (leftSpans.isNotEmpty) result.add(leftSpans);
    if (rightSpans.isNotEmpty) result.add(rightSpans);
    return result;
  }

  /// Cari titik split horizontal. Return null jika single-column.
  double? _detectColumnSplit(List<TextSpan> spans, double pageWidth) {
    // Cluster left-to-right dengan running max xRight.
    // Span whitespace-only diabaikan (fragment spasi pdfrx tidak punya
    // anchor posisi yang berarti).
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

    // Single-column / lebih dari 2 kolom (3+ kolom → fallback)
    if (clusters.length != 2) return null;

    // Split di titik tengah gap antara kolom kiri dan kanan
    final leftEdge = clusters[0].last.xRight;
    final rightEdge = clusters[1].first.xLeft;
    return (leftEdge + rightEdge) / 2;
  }
}
