import 'package:flutter/widgets.dart';

/// Koalesensi callback per frame: beberapa [schedule] dalam satu frame hanya
/// memicu satu [onFrame] — di awal frame berikutnya (fase transient, sebelum
/// build), sehingga [onFrame] yang memanggil `setState` langsung dirender di
/// frame yang sama tanpa jeda satu frame. Dipakai agar notifikasi controller
/// berfrekuensi tinggi tidak memaksa rebuild layar lebih dari sekali per frame.
class FrameCoalescer {
  FrameCoalescer({required this.onFrame});

  final VoidCallback onFrame;
  bool _scheduled = false;
  int _callbackId = 0;

  void schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // scheduleFrameCallback juga menjadwalkan frame baru — callback tidak
    // akan pernah dipanggil kalau engine tidak dibangunkan eksplisit.
    _callbackId = WidgetsBinding.instance.scheduleFrameCallback(_handleFrame);
  }

  void _handleFrame(Duration _) {
    _scheduled = false;
    _callbackId = 0;
    onFrame();
  }

  void dispose() {
    if (!_scheduled) return;
    WidgetsBinding.instance.cancelFrameCallbackWithId(_callbackId);
    _scheduled = false;
    _callbackId = 0;
  }
}
