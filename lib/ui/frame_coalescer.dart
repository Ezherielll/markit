import 'package:flutter/widgets.dart';

/// Per-frame callback coalescing: multiple [schedule] calls in a single frame only
/// trigger one [onFrame] — at the start of the next frame (transient phase, before
/// build), so [onFrame] calling `setState` renders in the same frame without a frame delay.
/// Used so high-frequency controller notifications do not force screen rebuilds more than once per frame.
class FrameCoalescer {
  FrameCoalescer({required this.onFrame});

  final VoidCallback onFrame;
  bool _scheduled = false;
  int _callbackId = 0;

  void schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // scheduleFrameCallback also schedules a new frame — callback will
    // never be called if engine is not explicitly woken up.
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
