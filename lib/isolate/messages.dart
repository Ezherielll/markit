import 'dart:isolate';

/// Inter-isolate messages for conversion pipeline.
///
/// All classes must be transferable via [SendPort] (plain data, no closures).
/// [jobId] maps message to file in batch queue.
library;

class StartConvert {
  StartConvert({
    required this.jobId,
    required this.pdfPath,
    required this.outputPath,
    this.formatName = 'pdf',
  });

  final String jobId;
  final String pdfPath;
  final String outputPath;

  /// [InputFormat] name (transferable String).
  final String formatName;
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

  /// Failed pages (1-based).
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

  /// [ConvertError] enum name for transferable data.
  final String errorType;
  final String message;
}

/// Sent main → worker to cancel conversion.
class CancelRequest {
  const CancelRequest();
}

/// Sent main → worker at start of new batch: resets cancel flag from
/// previous batch (worker is persistent across batches).
class ResetCancel {
  const ResetCancel();
}

/// Sent main → worker after batch completion — worker closes port & exits.
class Shutdown {
  const Shutdown();
}
