import 'dart:typed_data';

import '../core/input_format.dart';

/// Result of a single conversion job execution (platform-agnostic).
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

  /// Failed pages (1-based).
  final List<int> failedPages;
  final double bodyFontSize;

  /// Output file path (desktop/FileOutput); null for MemoryOutput (web).
  final String? outputPath;

  /// Resulting markdown content (web/MemoryOutput).
  final String? content;

  /// Error type ('corrupt'/'encrypted'/'noText'/etc) on failure.
  final String? errorType;
  final String? errorMessage;
}

/// Conversion job execution abstraction.
///
/// Desktop: [IsolateExecutor] (persistent worker isolate — pdfrx is unsafe
/// to repeatedly spawn/teardown in a single process).
/// Web: [InlineExecutor] (pipeline runs directly on main isolate, `Isolate.spawn`
/// is not supported on web).
abstract class ConversionExecutor {
  /// Initialize executor (spawn worker for isolate; no-op for inline).
  /// Called once before the first batch.
  Future<void> initialize();

  /// Run a single job.
  ///
  /// [pdfPath] used by desktop; [pdfBytes] used by web (no filesystem).
  /// [outputPath] = output path (desktop) or output filename (web).
  /// [onProgress] callback: (page, total, phase, elapsedMs).
  /// [format] input format — PDF → heuristic pipeline; others → semantic
  /// extractor.
  Future<JobExecutionResult> runJob({
    required String jobId,
    required String pdfPath,
    Uint8List? pdfBytes,
    required String outputPath,
    InputFormat format = InputFormat.pdf,
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  });

  /// Cancel active job.
  void cancel();

  /// Reset cancel flag between batches (persistent executor).
  void resetCancel();

  /// Shut down executor (worker shutdown for isolate; no-op for inline).
  Future<void> shutdown();
}
