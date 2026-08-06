import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/input_format.dart';
import '../core/pdfrx_source.dart';
import '../models/pdf_input.dart';
import 'conversion_executor.dart';
import 'conversion_executor_factory.dart';

/// Status satu file dalam batch queue.
enum JobStatus { queued, running, done, failed, cancelled }

/// Satu file PDF dalam antrean konversi.
class QueuedFile {
  QueuedFile({
    required this.id,
    required this.input,
    this.status = JobStatus.queued,
  });

  final String id;
  final PdfInput input;
  JobStatus status;

  /// Hasil probe page count (nullable sampai probe selesai).
  int? pageCount;
  double? bodyFontSize;

  /// Halaman gagal (1-based) — FR-10c.
  List<int> failedPages = const [];

  /// Progress per-job (running): halaman aktif & total halaman.
  int? currentPage;
  int? totalPages;

  double? get progressFraction {
    final total = totalPages ?? 0;
    final page = currentPage ?? 0;
    if (total <= 0) return null;
    return (page / total).clamp(0.0, 1.0);
  }

  /// Nama error ('corrupt'/'encrypted'/'noText'/dsb) bila gagal.
  String? errorType;
  String? errorMessage;

  /// Isi markdown hasil konversi (web/MemoryOutput); null di desktop.
  String? content;

  /// Path output (desktop: path dengan ekstensi apa pun → .md) atau nama
  /// file output (web).
  String get outputPath {
    final path = input.path;
    if (path != null) {
      return path.replaceFirst(
        RegExp(r'\.\w+$'),
        '.md',
      );
    }
    return input.outputName;
  }

  String get fileName => input.name;
}

/// Controller konversi batch (multi-file) yang bisa di-fake untuk widget test.
///
/// Semantik:
/// - [addFiles] menambah file ke queue (dedupe path), langsung probe page count.
/// - [convertAll] memproses file berurutan (sequential) via [ConversionExecutor]
///   (desktop: worker isolate persist; web: inline).
/// - [cancel] membatalkan job aktif + semua job queued (FR-11).
/// - [reset] mengosongkan queue + state.
abstract class ConversionController extends ChangeNotifier {
  bool get isRunning;

  /// Progress job aktif (0-based page).
  int? get currentPage;
  int? get totalPages;

  /// 0 = pass 1 (reading), 1 = pass 2 (converting).
  int get phase;

  /// Daftar file antrean (unmodifiable view).
  List<QueuedFile> get queue;

  /// Job yang sedang diproses (null bila idle).
  QueuedFile? get activeJob;

  /// Jumlah job selesai (done + failed + cancelled).
  int get completedCount;

  /// Jumlah job sukses.
  int get doneCount;

  void addFiles(List<PdfInput> inputs);

  /// Hapus file dari queue. Ditolak saat batch berjalan.
  void removeFile(String id);

  Future<void> convertAll();

  /// Batalkan batch: job aktif dibatalkan, sisanya → cancelled.
  void cancel();

  /// Kosongkan queue + state. Tidak berpengaruh saat batch berjalan.
  void reset();

  /// Hentikan executor (dipanggil saat app dispose). Aman dipanggil ulang.
  Future<void> shutdown();
}

/// Implementasi nyata: pipeline via [ConversionExecutor] (FR-08),
/// UI tetap responsif.
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

  @override
  bool get isRunning => _isRunning;

  /// Progress agregat = job running pertama (kompatibilitas UI lama);
  /// UI baru memakai progress per-job (QueuedFile.progressFraction).
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
    // Probe memuat PDFium di main isolate. Di desktop, worker isolate memuat
    // PDFium sendiri — dua init bersamaan menyebabkan deadlock. Karena itu
    // probe hanya dijalankan SEBELUM worker pertama; setelahnya pageCount
    // diisi dari hasil konversi.
    if (_executorReady) return;
    final future = _doProbe(job);
    _pendingProbes.add(future);
  }

  Future<void> _doProbe(QueuedFile job) async {
    try {
      final input = job.input;
      // Probe hanya untuk PDF — semantic extractor tidak butuh pageCount
      // (progress per item diisi saat konversi).
      if (input.format != InputFormat.pdf) return;
      final count = input.isBytes
          ? await PdfrxSource.probePageCountData(input.bytes!)
          : await PdfrxSource.probePageCount(input.path!);
      job.pageCount = count;
      notifyListeners();
    } catch (_) {
      // Divalidasi saat convert; probe gagal tidak fatal.
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

    // Tunggu semua probe selesai sebelum worker di-spawn (deadlock PDFium).
    final probes = [..._pendingProbes];
    _pendingProbes.clear();
    if (probes.isNotEmpty) {
      await Future.wait(probes);
    }

    // Executor persist untuk seluruh umur aplikasi (worker isolate di desktop;
    // inline di web).
    if (!_executorReady) {
      await _executor.initialize();
      _executorReady = true;
    }
    _executor.resetCancel();

    _isRunning = true;
    notifyListeners();

    try {
      // Semua job queued dijalankan BERSAMAAN (concurrent interleaved) —
      // PDFium aman multi-dokumen dalam satu worker (tervalidasi M1).
      final jobs = _queue
          .where((j) =>
              j.status == JobStatus.queued ||
              j.status == JobStatus.failed)
          .toList();

      await Future.wait([
        for (final job in jobs) _runOneConcurrent(job),
      ]);
    } finally {
      // Sisa queue yang belum diproses saat cancel → cancelled.
      if (_cancelRequested) {
        for (final job in _queue) {
          if (job.status == JobStatus.queued) {
            job.status = JobStatus.cancelled;
          }
        }
      }
    }

    _isRunning = false;
    notifyListeners();
  }

  /// Jalankan satu job di executor (parallel-friendly: tiap job punya
  /// callback progress sendiri yang update field job tsb).
  Future<void> _runOneConcurrent(QueuedFile job) async {
    if (_cancelRequested) {
      job.status = JobStatus.cancelled;
      return;
    }

    job.status = JobStatus.running;
    job.currentPage = 0;
    job.totalPages = null;
    notifyListeners();

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
    notifyListeners();
  }

  @override
  Future<void> shutdown() async {
    if (_isRunning) return;
    _executorReady = false;
    await _executor.shutdown();
  }
}
