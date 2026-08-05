import 'dart:typed_data';

/// Hasil eksekusi satu job konversi (platform-agnostic).
class JobExecutionResult {
  JobExecutionResult({
    required this.success,
    required this.pageCount,
    required this.failedPages,
    required this.bodyFontSize,
    this.outputPath,
    this.content,
    this.errorType,
    this.errorMessage,
  });

  JobExecutionResult.failure(String errorType, String errorMessage)
      : this(
          success: false,
          pageCount: 0,
          failedPages: const [],
          bodyFontSize: 0,
          errorType: errorType,
          errorMessage: errorMessage,
        );

  final bool success;
  final int pageCount;

  /// Halaman gagal (1-based) — FR-10c.
  final List<int> failedPages;
  final double bodyFontSize;

  /// Path file output (desktop/FileOutput); null untuk MemoryOutput (web).
  final String? outputPath;

  /// Isi markdown hasil konversi (web/MemoryOutput).
  final String? content;

  /// Nama error ('corrupt'/'encrypted'/'noText'/dsb) bila gagal.
  final String? errorType;
  final String? errorMessage;
}

/// Abstraksi eksekusi job konversi.
///
/// Desktop: [IsolateExecutor] (worker isolate persist — pdfrx tidak aman
/// di-spawn/teardown berulang dalam satu proses).
/// Web: [InlineExecutor] (pipeline langsung di main isolate, `Isolate.spawn`
/// tidak didukung di web).
abstract class ConversionExecutor {
  /// Siapkan executor (spawn worker untuk isolate; no-op untuk inline).
  /// Dipanggil sekali sebelum batch pertama.
  Future<void> initialize();

  /// Jalankan satu job.
  ///
  /// [pdfPath] dipakai desktop; [pdfBytes] dipakai web (tanpa filesystem).
  /// [outputPath] = path output (desktop) atau nama file output (web).
  /// [onProgress] callback: (page, total, phase, elapsedMs).
  Future<JobExecutionResult> runJob({
    required String jobId,
    required String pdfPath,
    Uint8List? pdfBytes,
    required String outputPath,
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  });

  /// Batalkan job aktif.
  void cancel();

  /// Reset flag cancel antar batch (executor persist).
  void resetCancel();

  /// Hentikan executor (worker shutdown untuk isolate; no-op untuk inline).
  Future<void> shutdown();
}
