import 'dart:async';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

import 'convert_isolate.dart';
import 'messages.dart';

/// Controller konversi yang bisa di-fake untuk widget test.
abstract class ConversionController extends ChangeNotifier {
  bool get isRunning;
  int? get currentPage;
  int? get totalPages;

  /// 0 = pass 1 (reading), 1 = pass 2 (converting).
  int get phase;
  String? get outputPath;
  String? get errorType;
  String? get errorMessage;

  /// Halaman gagal (1-based) dari hasil konversi (FR-10c).
  List<int> get failedPages;

  /// Proxy fontSize body terdeteksi (untuk info kartu).
  double? get bodyFontSize;

  Future<void> convert({
    required String pdfPath,
    required String outputPath,
  });

  void cancel();

  /// Bersihkan state hasil/error agar UI kembali ke state awal.
  /// Tidak berpengaruh saat konversi berjalan.
  void reset();
}

/// Implementasi nyata: pipeline di background isolate (FR-08), UI tetap responsif.
class IsolateConversionController extends ConversionController {
  IsolatePorts? _ports;
  bool _isRunning = false;
  int? _currentPage;
  int? _totalPages;
  int _phase = 1;
  String? _outputPath;
  String? _errorType;
  String? _errorMessage;
  List<int> _failedPages = const [];
  double? _bodyFontSize;

  @override
  bool get isRunning => _isRunning;

  @override
  int? get currentPage => _currentPage;

  @override
  int? get totalPages => _totalPages;

  @override
  int get phase => _phase;

  @override
  String? get outputPath => _outputPath;

  @override
  List<int> get failedPages => _failedPages;

  @override
  double? get bodyFontSize => _bodyFontSize;

  @override
  String? get errorType => _errorType;

  @override
  String? get errorMessage => _errorMessage;

  @override
  Future<void> convert({
    required String pdfPath,
    required String outputPath,
  }) async {
    if (_isRunning) return;
    _reset();
    _isRunning = true;
    notifyListeners();

    // Urutan pesan dari worker:
    // 1. SendPort command   (dikirim segera oleh convertIsolateMain)
    // 2. SendPort cancel    (dikirim di awal _run)
    // 3. Progress / Done / Failed
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(
      convertIsolateMain,
      receivePort.sendPort,
    );

    SendPort? commandPort;
    SendPort? cancelSender;
    final sub = receivePort.listen((message) {
      if (commandPort == null) {
        commandPort = message as SendPort;
        // Mulai konversi segera; cancel port worker menyusul.
        commandPort!.send(StartConvert(
          pdfPath: pdfPath,
          outputPath: outputPath,
        ));
        return;
      }
      if (cancelSender == null && message is SendPort) {
        cancelSender = message;
        return;
      }
      _handleMessage(message);
    });

    _ports = IsolatePorts(
      isolate: isolate,
      receivePort: receivePort,
      subscription: sub,
      cancelPortReady: () => cancelSender,
    );
    notifyListeners();
  }

  @override
  void cancel() {
    _ports?.cancelPortReady()?.send(const CancelRequest());
  }

  @override
  void reset() {
    if (_isRunning) return;
    _reset();
    notifyListeners();
  }

  void _reset() {
    _currentPage = null;
    _totalPages = null;
    _phase = 1;
    _outputPath = null;
    _errorType = null;
    _errorMessage = null;
    _failedPages = const [];
    _bodyFontSize = null;
  }

  void _handleMessage(dynamic message) {
    if (message is ConvertProgress) {
      _currentPage = message.page;
      _totalPages = message.total;
      _phase = message.phase;
      notifyListeners();
    } else if (message is ConvertDone) {
      _outputPath = message.outputPath;
      _failedPages = message.failedPages;
      _bodyFontSize = message.bodyFontSize;
      _finish();
    } else if (message is ConvertFailed) {
      _errorType = message.errorType;
      _errorMessage = message.message;
      _finish();
    }
  }

  void _finish() {
    _isRunning = false;
    _ports?.dispose();
    _ports = null;
    notifyListeners();
  }
}

class IsolatePorts {
  IsolatePorts({
    required this.isolate,
    required this.receivePort,
    required this.subscription,
    required this.cancelPortReady,
  });

  final Isolate isolate;
  final ReceivePort receivePort;
  final StreamSubscription<dynamic> subscription;

  /// SendPort cancel worker, tersedia setelah pesan kedua diterima.
  final SendPort? Function() cancelPortReady;

  void dispose() {
    subscription.cancel();
    receivePort.close();
    isolate.kill();
  }
}
