/// Pesan antar-isolate untuk pipeline konversi (FR-08, FR-11).
///
/// Semua kelas harus transferable via [SendPort] (plain data, tanpa closure).
/// [jobId] memetakan pesan ke file di batch queue (multi-file).
library;

import 'dart:isolate';

class StartConvert {
  StartConvert({
    required this.jobId,
    required this.pdfPath,
    required this.outputPath,
  });

  final String jobId;
  final String pdfPath;
  final String outputPath;
}

class ConvertProgress {
  ConvertProgress({
    required this.jobId,
    required this.page,
    required this.total,
    required this.elapsedMs,
    this.phase = 1,
  });

  final String jobId;
  final int page;
  final int total;
  final int elapsedMs;

  /// 0 = pass 1 (reading/histogram), 1 = pass 2 (converting).
  final int phase;
}

class ConvertDone {
  ConvertDone({
    required this.jobId,
    required this.outputPath,
    required this.pageCount,
    required this.failedPages,
    required this.elapsedMs,
    required this.bodyFontSize,
    required this.emptyPages,
  });

  final String jobId;
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
    required this.jobId,
    required this.errorType,
    required this.message,
  });

  final String jobId;

  /// Nama enum [ConvertError] agar transferable.
  final String errorType;
  final String message;
}

/// Dikirim main → worker untuk membatalkan konversi (FR-11).
class CancelRequest {
  const CancelRequest();
}

/// Dikirim main → worker di awal batch baru: reset flag cancel dari batch
/// sebelumnya (worker bersifat persist antar batch).
class ResetCancel {
  const ResetCancel();
}

/// Dikirim main → worker setelah batch selesai — worker menutup port & exit.
class Shutdown {
  const Shutdown();
}
