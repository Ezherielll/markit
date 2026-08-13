import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../core/format_catalog.dart';
import '../core/input_format.dart';
import '../core/pdfrx_source.dart';
import '../models/pdf_input.dart';
import 'conversion_executor.dart';
import 'conversion_executor_factory.dart';

/// Status of a single file in the batch queue.
enum JobStatus { queued, running, done, failed, cancelled }

/// Single PDF/document file in conversion queue.
class QueuedFile {
  QueuedFile({
    required this.id,
    required this.input,
    this.status = JobStatus.queued,
    String? outputPath,
  }) : outputPath = outputPath ?? _defaultOutputPath(input);

  final String id;
  final PdfInput input;
  JobStatus status;

  /// Probe page count result (nullable until probe finishes).
  int? pageCount;
  double? bodyFontSize;

  /// Failed pages (1-based).
  List<int> failedPages = const [];

  /// Per-job running progress: active page & total pages.
  int? currentPage;
  int? totalPages;

  double? get progressFraction {
    final total = totalPages ?? 0;
    final page = currentPage ?? 0;
    if (total <= 0) return null;
    return (page / total).clamp(0.0, 1.0);
  }

  /// Error type ('corrupt'/'encrypted'/'noText'/etc) on failure.
  String? errorType;
  String? errorMessage;

  /// Markdown content result (web/MemoryOutput); null on desktop.
  String? content;

  /// Output path (desktop: source path with any extension → .md; web:
  /// output filename). Mutable — updated after user selects target folder
  /// ("location picker" phase), so UI ("Open folder") remains consistent.
  String outputPath;

  static String _defaultOutputPath(PdfInput input) {
    final path = input.path;
    if (path != null) {
      return path.replaceFirst(RegExp(r'\.\w+$'), '.md');
    }
    return input.outputName;
  }

  String get fileName => input.name;
}

/// Batch conversion controller (multi-file) fakeable for widget tests.
///
/// Semantics:
/// - [addFiles] adds files to queue (path deduplication), probes page count immediately.
/// - [convertAll] processes files sequentially/concurrently via [ConversionExecutor]
///   (desktop: persistent worker isolate; web: inline).
/// - [cancel] cancels active job + all queued jobs.
/// - [reset] clears queue + state.
abstract class ConversionController extends ChangeNotifier {
  bool get isRunning;

  /// Active job progress (0-based page).
  int? get currentPage;
  int? get totalPages;

  /// 0 = pass 1 (reading), 1 = pass 2 (converting).
  int get phase;

  /// Queue file list (unmodifiable view).
  List<QueuedFile> get queue;

  /// Currently active job (null if idle).
  QueuedFile? get activeJob;

  /// Count of completed jobs (done + failed + cancelled).
  int get completedCount;

  /// Count of successful jobs.
  int get doneCount;

  void addFiles(List<PdfInput> inputs);

  /// Remove file from queue. Rejected while batch is running.
  void removeFile(String id);

  Future<void> convertAll();

  /// Cancel batch: active job cancelled, remaining → cancelled.
  void cancel();

  /// Clear queue + state. No-op while batch is running.
  void reset();

  /// Shut down executor (called on app dispose). Safe to call multiple times.
  Future<void> shutdown();

  /// Delete batch output temp directory (desktop). Called after Save flow
  /// completes (unsaved files discarded), on reset, and on shutdown.
  Future<void> cleanupTempOutputs();
}

/// Concrete implementation: pipeline via [ConversionExecutor],
/// keeping UI responsive.
class BatchConversionController extends ConversionController {
  BatchConversionController({ConversionExecutor? executor})
      : _executor = executor ?? createConversionExecutor();

  final ConversionExecutor _executor;
  final List<QueuedFile> _queue = [];
  final List<Future<void>> _pendingProbes = [];
  bool _isRunning = false;
  bool _executorReady = false;
  int _phase = 1;
  bool _cancelRequested = false;
  int _idCounter = 0;

  /// Per-batch temp directory for .md results (desktop). Conversion DOES NOT
  /// write to source folder — new files are "saved" when user presses
  /// Save button and selects destination directory (temp → destination move flow).
  Directory? _tempOutputDir;

  @override
  bool get isRunning => _isRunning;

  /// Aggregate progress = first running job (legacy UI compatibility);
  /// new UI uses per-job progress (QueuedFile.progressFraction).
  @override
  int? get currentPage {
    final running = _queue.where((f) => f.status == JobStatus.running);
    return running.isEmpty ? null : running.first.currentPage;
  }

  @override
  int? get totalPages {
    final running = _queue.where((f) => f.status == JobStatus.running);
    return running.isEmpty ? null : running.first.totalPages;
  }

  @override
  int get phase => _phase;

  @override
  List<QueuedFile> get queue => List.unmodifiable(_queue);

  @override
  QueuedFile? get activeJob {
    for (final f in _queue) {
      if (f.status == JobStatus.running) return f;
    }
    return null;
  }

  @override
  int get completedCount =>
      _queue.where((f) => f.status != JobStatus.queued).length;

  @override
  int get doneCount => _queue.where((f) => f.status == JobStatus.done).length;

  @override
  void addFiles(List<PdfInput> inputs) {
    if (_isRunning) return;
    final existing = _queue.map((f) => f.input.dedupeKey).toSet();
    for (final input in inputs) {
      if (existing.contains(input.dedupeKey)) continue;
      existing.add(input.dedupeKey);
      _queue.add(QueuedFile(
        id: 'job-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
        input: input,
      ));
    }
    notifyListeners();
    for (final job in _queue) {
      if (job.pageCount == null) _probe(job);
    }
  }

  Future<void> _probe(QueuedFile job) async {
    // Probe loads PDFium on main isolate. On desktop, worker isolate loads
    // PDFium itself — two simultaneous inits cause deadlocks. Thus probe
    // is run only BEFORE first worker; afterwards pageCount is filled from
    // conversion result.
    if (_executorReady) return;
    final future = _doProbe(job);
    _pendingProbes.add(future);
  }

  Future<void> _doProbe(QueuedFile job) async {
    try {
      final input = job.input;
      // Probe only for PDF — semantic extractors do not need pageCount
      // (per-item progress filled during conversion).
      if (input.format != InputFormat.pdf) return;
      final count = input.isBytes
          ? await PdfrxSource.probePageCountData(input.bytes!)
          : await PdfrxSource.probePageCount(input.path!);
      job.pageCount = count;
      notifyListeners();
    } catch (_) {
      // Validated during convert; failed probe is non-fatal.
    }
  }

  @override
  void removeFile(String id) {
    if (_isRunning) return;
    _queue.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  @override
  Future<void> convertAll() async {
    if (_isRunning) return;
    _cancelRequested = false;

    await _awaitPendingProbes();

    // Persistent executor for entire application lifetime (worker isolate on desktop;
    // inline on web).
    if (!_executorReady) {
      await _executor.initialize();
      _executorReady = true;
    }
    _executor.resetCancel();

    _isRunning = true;
    notifyListeners();

    try {
      // All queued jobs run CONCURRENTLY (interleaved) —
      // PDFium is multi-document safe within a single worker.
      final jobs = _queue
          .where((j) =>
              j.status == JobStatus.queued ||
              j.status == JobStatus.failed)
          .toList();

      await _assignTempOutputPaths(jobs);

      await Future.wait([
        for (final job in jobs) _runOneConcurrent(job),
      ]);
    } finally {
      _cancelRemainingQueuedJobs();
      // ALWAYS reset running state, even when the batch above fails with an
      // unexpected exception (e.g. filesystem unavailable on web). Without
      // this, `_isRunning` stays true forever and the UI is wedged on
      // "Processing" with jobs that never run.
      _isRunning = false;
      notifyListeners();
    }
  }

  /// Wait for all probes to finish before spawning worker (PDFium deadlock).
  Future<void> _awaitPendingProbes() async {
    final probes = [..._pendingProbes];
    _pendingProbes.clear();
    if (probes.isNotEmpty) {
      await Future.wait(probes);
    }
  }

  /// Location picker phase: desktop conversion result written to TEMP dir
  /// (not source folder) — file not automatically saved; moved to destination
  /// directory when user presses Save button. Null on web (no filesystem) —
  /// jobs keep their output names and run normally.
  Future<void> _assignTempOutputPaths(List<QueuedFile> jobs) async {
    final tempDir = await ensureTempOutputDir();
    if (tempDir == null) return;
    for (final job in jobs) {
      if (job.input.path != null) {
        job.outputPath = '${tempDir.path}/${job.input.outputName}';
      }
    }
  }

  /// Remaining unprocessed queue during cancel → cancelled.
  void _cancelRemainingQueuedJobs() {
    if (!_cancelRequested) return;
    for (final job in _queue) {
      if (job.status == JobStatus.queued) {
        job.status = JobStatus.cancelled;
      }
    }
  }

  /// Run a single job on executor (parallel-friendly: each job has
  /// its own progress callback updating its job fields).
  Future<void> _runOneConcurrent(QueuedFile job) async {
    if (_cancelRequested) {
      job.status = JobStatus.cancelled;
      return;
    }

    job.status = JobStatus.running;
    job.currentPage = 0;
    job.totalPages = null;
    notifyListeners();

    // Legacy formats (OLE2: .doc/.ppt/.pps/.pot/.xls/.xlsb) detected but
    // lack parsers — fail CLEARLY ("not supported yet"), not "corrupt".
    // Batch continues to next file.
    if (isLegacyFormatExtension(job.input.format, job.input.name)) {
      final ext = job.input.name.toLowerCase().split('.').last;
      job.status = JobStatus.failed;
      job.errorType = 'unsupported';
      job.errorMessage =
          'Format ${job.input.format.label} (.$ext) is not yet supported for conversion.';
      notifyListeners();
      return;
    }

    try {
      final result = await _executor.runJob(
        jobId: job.id,
        pdfPath: job.input.path ?? '',
        pdfBytes: job.input.bytes,
        outputPath: job.outputPath,
        format: job.input.format,
        onProgress: (page, total, phase, elapsedMs) {
          job.currentPage = page;
          job.totalPages = total;
          _phase = phase;
          notifyListeners();
        },
      );

      if (_cancelRequested) {
        job.status = JobStatus.cancelled;
      } else if (result.success) {
        job.status = JobStatus.done;
        job.pageCount = result.pageCount;
        job.failedPages = result.failedPages;
        job.bodyFontSize = result.bodyFontSize;
        job.content = result.content;
      } else {
        job.status = JobStatus.failed;
        job.errorType = result.errorType;
        job.errorMessage = result.errorMessage;
      }
    } catch (e) {
      // Executor internal bug must not blow up the entire batch —
      // this job marked failed, batch continues.
      job.status = JobStatus.failed;
      job.errorType = 'corrupt';
      job.errorMessage = 'Unexpected error during conversion: $e';
    }
    notifyListeners();
  }

  @override
  void cancel() {
    _cancelRequested = true;
    _executor.cancel();
    notifyListeners();
  }

  @override
  void reset() {
    if (_isRunning) return;
    _queue.clear();
    _phase = 1;
    _cancelRequested = false;
    // Discard previous unsaved batch temp output
    // (synchronous — reset is a non-async operation).
    _discardTempOutputSync();
    notifyListeners();
  }

  /// Synchronously delete batch temp directory (reset).
  void _discardTempOutputSync() {
    final dir = _tempOutputDir;
    _tempOutputDir = null;
    if (dir == null || !dir.existsSync()) return;
    try {
      dir.deleteSync(recursive: true);
    } on FileSystemException {
      // File temporarily locked (Windows) — cleaned up in next batch.
    }
  }

  @override
  Future<void> shutdown() async {
    if (_isRunning) return;
    _executorReady = false;
    await _executor.shutdown();
    await cleanupTempOutputs();
  }

  /// Create (or reuse) batch temp directory for desktop .md results.
  ///
  /// Returns null on web — the web build has no filesystem (dart:io is a
  /// stub there; `Directory.systemTemp` throws UnsupportedError at runtime,
  /// which used to wedge the whole batch on "Processing" before any job
  /// started). Public as a seam so tests can simulate web / fs failures.
  @visibleForTesting
  Future<Directory?> ensureTempOutputDir() async {
    if (kIsWeb) return null;
    final existing = _tempOutputDir;
    if (existing != null && existing.existsSync()) return existing;
    final dir = await Directory.systemTemp.createTemp('markit_batch');
    _tempOutputDir = dir;
    return dir;
  }

  @override
  Future<void> cleanupTempOutputs() async {
    final dir = _tempOutputDir;
    _tempOutputDir = null;
    if (dir != null && dir.existsSync()) {
      await dir.delete(recursive: true);
    }
  }
}
