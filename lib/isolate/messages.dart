/// Pesan antar-isolate untuk pipeline konversi (FR-08, FR-11).
///
/// Semua kelas harus transferable via [SendPort] (plain data, tanpa closure).
library;

import 'dart:isolate';

class StartConvert {
  StartConvert({
    required this.pdfPath,
    required this.outputPath,
  });

  final String pdfPath;
  final String outputPath;
}

class ConvertProgress {
  ConvertProgress({
    required this.page,
    required this.total,
    required this.elapsedMs,
    this.phase = 1,
  });

  final int page;
  final int total;
  final int elapsedMs;

  /// 0 = pass 1 (reading/histogram), 1 = pass 2 (converting).
  final int phase;
}

class ConvertDone {
  ConvertDone({
    required this.outputPath,
    required this.pageCount,
    required this.failedPages,
    required this.elapsedMs,
    required this.bodyFontSize,
    required this.emptyPages,
  });

  final String outputPath;
  final int pageCount;

  /// Halaman gagal (1-based) — FR-10c.
  final List<int> failedPages;
  final int elapsedMs;
  final double bodyFontSize;
  final int emptyPages;
}

class ConvertFailed {
  ConvertFailed({
    required this.errorType,
    required this.message,
  });

  /// Nama enum [ConvertError] sebagai string agar transferable.
  final String errorType;
  final String message;
}

/// Dikirim main → worker untuk membatalkan konversi (FR-11).
class CancelRequest {
  const CancelRequest();
}
