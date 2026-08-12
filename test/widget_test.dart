import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/app.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/screens/home_screen.dart';

/// Fake controller minimal: simulasi batch tanpa isolate.
class _FakeController extends ConversionController {
  final List<QueuedFile> _queue = [];
  bool _isRunning = false;
  int _id = 0;
  int convertAllCalls = 0;

  @override
  bool get isRunning => _isRunning;

  @override
  int? get currentPage => null;

  @override
  int? get totalPages => null;

  @override
  int get phase => 1;

  @override
  List<QueuedFile> get queue => List.unmodifiable(_queue);

  @override
  QueuedFile? get activeJob => null;

  @override
  int get completedCount =>
      _queue.where((f) => f.status != JobStatus.queued).length;

  @override
  int get doneCount => _queue.where((f) => f.status == JobStatus.done).length;

  void add(PdfInput input) {
    final job = QueuedFile(id: 'j${_id++}', input: input);
    job.pageCount = 10;
    _queue.add(job);
    notifyListeners();
  }

  @override
  void addFiles(List<PdfInput> inputs) {
    for (final input in inputs) {
      add(input);
    }
  }

  @override
  void removeFile(String id) {
    _queue.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  @override
  Future<void> convertAll() async {
    convertAllCalls++;
    _isRunning = true;
    notifyListeners();
    for (final job in [..._queue]) {
      job.status = JobStatus.running;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      job.status = JobStatus.done;
      notifyListeners();
    }
    _isRunning = false;
    notifyListeners();
  }

  @override
  void cancel() {}

  @override
  void reset() {
    _queue.clear();
    _isRunning = false;
    notifyListeners();
  }

  @override
  Future<void> shutdown() async {}
}

void main() {
  testWidgets('app boots to home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PdflowApp());
    expect(find.text('MarkIt'), findsOneWidget);
    expect(find.text('Choose files'), findsOneWidget);
  });

  testWidgets(
      'convert all: dialog overwrite saat .md sudah ada, konfirmasi lanjut konversi (FR-12)',
      (WidgetTester tester) async {
    final dir = Directory.systemTemp.createTempSync('markit_convert_test');
    addTearDown(() async {
      // Windows: viewer masih bisa meminjam handle file sesaat — retry.
      for (var attempt = 0; attempt < 10; attempt++) {
        try {
          dir.deleteSync(recursive: true);
          return;
        } on FileSystemException {
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }
    });
    File('${dir.path}/doc.md').writeAsStringSync('old output');

    final controller = _FakeController();
    controller.add(PdfInput(name: 'doc.pdf', path: '${dir.path}/doc.pdf'));

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(home: HomeScreen(controller: controller)),
    );

    // Konflik terdeteksi → dialog overwrite muncul sebelum konversi jalan.
    // File.exists() adalah IO nyata → interaksi dijalankan di luar fake-async
    // zone (runAsync), rendering tetap lewat pump.
    await tester.runAsync(() async {
      await tester.tap(find.text('Convert (1)'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();
    expect(find.text(Strings.overwriteTitle), findsOneWidget);
    expect(controller.convertAllCalls, 0);

    await tester.runAsync(() async {
      await tester.tap(find.text(Strings.overwriteConfirm));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    // Konversi selesai (real-timer di runAsync) → auto-select job done →
    // viewer memuat .md dari disk (IO nyata) — beri kesempatan selesai.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    // Pump berbatas (bukan pumpAndSettle): skeleton viewer punya animasi
    // repeat tak berujung — sama dengan konvensi home_screen_test.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 500));

    // Setelah konfirmasi: batch dijalankan, job selesai, summary tampil.
    expect(controller.convertAllCalls, 1);
    expect(controller.doneCount, 1);
    expect(find.text(Strings.clearAll), findsOneWidget);
  });
}
