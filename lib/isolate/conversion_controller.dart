import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import '../core/pdfrx_source.dart';
import 'convert_isolate.dart';
import 'messages.dart';

/// Status satu file dalam batch queue.
enum JobStatus { queued, running, done, failed, cancelled }

/// Satu file PDF dalam antrean konversi.
class QueuedFile {
  QueuedFile({
    required this.id,
    required this.pdfPath,
    this.status = JobStatus.queued,
  });

  final String id;
  final String pdfPath;
  JobStatus status;

  /// Hasil probe page count (nullable sampai probe selesai).
  int? pageCount;
  double? bodyFontSize;

  /// Halaman gagal (1-based) — FR-10c.
  List<int> failedPages = const [];

  /// Nama error ('corrupt'/'encrypted'/'noText'/dsb) bila gagal.
  String? errorType;
  String? errorMessage;

  String get outputPath => pdfPath.replaceFirst(
        RegExp(r'\.pdf$', caseSensitive: false),
        '.md',
      );

  String get fileName => pdfPath.split(RegExp(r'[\\/]')).last;
}

/// Controller konversi batch (multi-file) yang bisa di-fake untuk widget test.
///
/// Semantik:
/// - [addFiles] menambah file ke queue (dedupe path), langsung probe page count.
/// - [convertAll] memproses file berurutan (sequential) di SATU worker isolate
///   persist — pdfrx membuat internal engine worker per isolate, spawn ulang
///   per file terbukti crash.
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

  void addFiles(List<String> paths);

  /// Hapus file dari queue. Ditolak saat batch berjalan.
  void removeFile(String id);

  Future<void> convertAll();

  /// Batalkan batch: job aktif dibatalkan, sisanya → cancelled.
  void cancel();

  /// Kosongkan queue + state. Tidak berpengaruh saat batch berjalan.
  void reset();
}

/// Implementasi nyata: pipeline di background isolate (FR-08), UI tetap responsif.
class IsolateConversionController extends ConversionController {
  IsolatePorts? _ports;
  final List<QueuedFile> _queue = [];
  final List<Future<void>> _pendingProbes = [];
  bool _isRunning = false;
  int? _currentPage;
  int? _totalPages;
  int _phase = 1;
  bool _cancelRequested = false;
  int _idCounter = 0;

  @override
  bool get isRunning => _isRunning;

  @override
  int? get currentPage => _currentPage;

  @override
  int? get totalPages => _totalPages;

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
  void addFiles(List<String> paths) {
    if (_isRunning) return;
    final existing = _queue.map((f) => f.pdfPath).toSet();
    for (final path in paths) {
      if (existing.contains(path)) continue;
      existing.add(path);
      _queue.add(QueuedFile(
        id: 'job-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
        pdfPath: path,
      ));
    }
    notifyListeners();
    for (final job in _queue) {
      if (job.pageCount == null) _probe(job);
    }
  }

  Future<void> _probe(QueuedFile job) async {
    // Probe memuat PDFium di main isolate (membuat PdfrxEngineWorker main).
    // Kalau worker batch sudah pernah dibuat, dua engine worker hidup
    // bersamaan → crash "Cannot invoke native callback from a different
    // isolate". Karena itu probe hanya dijalankan SEBELUM worker pertama;
    // setelahnya pageCount diisi dari ConvertDone.
    if (_ports != null) return;
    final future = _doProbe(job);
    _pendingProbes.add(future);
  }

  Future<void> _doProbe(QueuedFile job) async {
    try {
      final count = await PdfrxSource.probePageCount(job.pdfPath);
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

    // Satu worker PERSIST untuk seluruh umur aplikasi — pdfrx tidak aman
    // di-spawn/teardown berulang dalam satu proses (engine worker internal
    // crash "Cannot invoke native callback from a different isolate").
    _ports ??= await _spawnWorker();
    final ports = _ports!;
    ports.commandPort?.send(const ResetCancel());

    _isRunning = true;
    notifyListeners();

    try {
      for (final job in [..._queue]) {
        if (_cancelRequested) break;

        // Skip job yang sudah selesai.
        if (job.status == JobStatus.done || job.status == JobStatus.cancelled) {
          continue;
        }

        job.status = JobStatus.running;
        notifyListeners();

        final ok = await _runOne(ports, job);
        if (_cancelRequested) {
          job.status = JobStatus.cancelled;
        } else if (ok) {
          job.status = JobStatus.done;
        } else {
          job.status = JobStatus.failed;
        }
        notifyListeners();
      }
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

    _currentPage = null;
    _totalPages = null;
    _phase = 1;
    _isRunning = false;
    notifyListeners();
  }

  /// Spawn satu worker persist + wire ports.
  Future<IsolatePorts> _spawnWorker() async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      convertIsolateMain,
      receivePort.sendPort,
    );

    final exitPort = ReceivePort();
    isolate.addOnExitListener(exitPort.sendPort);

    final ports = IsolatePorts(
      isolate: isolate,
      receivePort: receivePort,
      exitPort: exitPort,
    );

    // Handler default (langsung aktif): tangkap command/cancel port yang
    // dikirim worker saat spawn — jangan sampai terlewat sebelum job pertama.
    void Function(dynamic message)? jobHandler;
    ports.subscription = receivePort.listen((message) {
      if (message is SendPort && ports.commandPort == null) {
        ports.commandPort = message;
        return;
      }
      if (message is SendPort && ports.cancelSender == null) {
        ports.cancelSender = message;
        return;
      }
      jobHandler?.call(message);
    });
    ports.setHandler = (h) => jobHandler = h;

    // Pastikan port worker sudah terdaftar sebelum job pertama dikirim.
    final deadline = DateTime.now().add(const Duration(seconds: 10));
    while ((ports.commandPort == null || ports.cancelSender == null) &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return ports;
  }

  /// Kirim satu job ke worker; kembalikan true bila sukses.
  Future<bool> _runOne(IsolatePorts ports, QueuedFile job) async {
    final completer = Completer<bool>();

    ports.setHandler!.call((message) {
      if (message is ConvertProgress) {
        _currentPage = message.page;
        _totalPages = message.total;
        _phase = message.phase;
        notifyListeners();
      } else if (message is ConvertDone) {
        job.pageCount = message.pageCount;
        job.failedPages = message.failedPages;
        job.bodyFontSize = message.bodyFontSize;
        if (!completer.isCompleted) completer.complete(true);
      } else if (message is ConvertFailed) {
        job.errorType = message.errorType;
        job.errorMessage = message.message;
        if (!completer.isCompleted) completer.complete(false);
      }
    });

    ports.commandPort!.send(StartConvert(
      jobId: job.id,
      pdfPath: job.pdfPath,
      outputPath: job.outputPath,
    ));

    return completer.future.timeout(
      const Duration(minutes: 30),
      onTimeout: () => false,
    );
  }

  @override
  void cancel() {
    _cancelRequested = true;
    _ports?.cancelSender?.send(const CancelRequest());
    notifyListeners();
  }

  @override
  void reset() {
    if (_isRunning) return;
    _queue.clear();
    _currentPage = null;
    _totalPages = null;
    _phase = 1;
    _cancelRequested = false;
    notifyListeners();
  }

  /// Bersihkan worker persist (dipanggil saat controller tidak dipakai lagi,
  /// misal di app dispose). Tidak wajib — worker ikut mati saat proses exit.
  Future<void> shutdown() async {
    if (_isRunning) return;
    final ports = _ports;
    _ports = null;
    if (ports != null) {
      ports.commandPort?.send(const Shutdown());
      await ports.dispose();
    }
  }
}

class IsolatePorts {
  IsolatePorts({
    required this.isolate,
    required this.receivePort,
    required this.exitPort,
  });

  final Isolate isolate;
  final ReceivePort receivePort;
  late StreamSubscription<dynamic> subscription;
  final ReceivePort exitPort;

  /// Command port worker (diterima saat spawn).
  SendPort? commandPort;

  /// Cancel port worker (diterima saat spawn).
  SendPort? cancelSender;

  /// Ganti handler pesan untuk job aktif (Progress/Done/Failed).
  void Function(void Function(dynamic) handler)? setHandler;

  Future<void> dispose() async {
    await subscription.cancel();
    receivePort.close();
    // Tunggu worker exit (setelah Shutdown) — worker sendiri yang menutup
    // command port & PDFium; TIDAK boleh di-kill paksa (native callback
    // PDFium crash "Cannot invoke native callback from a different isolate").
    await exitPort.first.timeout(
      const Duration(seconds: 5),
      onTimeout: () => null,
    );
    exitPort.close();
  }
}
