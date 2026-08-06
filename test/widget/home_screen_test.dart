import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/isolate/conversion_controller.dart';
import 'package:pdflow/models/pdf_input.dart';
import 'package:pdflow/theme/theme_controller.dart';
import 'package:pdflow/ui/screens/home_screen.dart';
import 'package:pdflow/ui/widgets/drop_zone.dart';
import 'package:pdflow/ui/widgets/document_viewer.dart';
import 'package:pdflow/ui/widgets/file_card.dart';
import 'package:pdflow/ui/widgets/header/status_pill.dart';

/// Fake controller: simulasi batch tanpa isolate.
class FakeConversionController extends ConversionController {
  final List<QueuedFile> _queue = [];
  bool _isRunning = false;
  int? _page;
  int? _total;
  int _phase = 1;
  bool cancelCalled = false;
  bool failAll = false;
  int _id = 0;

  @override
  bool get isRunning => _isRunning;

  @override
  int? get currentPage => _page;

  @override
  int? get totalPages => _total;

  @override
  int get phase => _phase;

  @override
  List<QueuedFile> get queue => List.unmodifiable(_queue);

  @override
  QueuedFile? get activeJob =>
      _queue.where((f) => f.status == JobStatus.running).firstOrNull;

  @override
  int get completedCount =>
      _queue.where((f) => f.status != JobStatus.queued).length;

  @override
  int get doneCount => _queue.where((f) => f.status == JobStatus.done).length;

  @override
  void addFiles(List<PdfInput> inputs) {
    for (final input in inputs) {
      final job = QueuedFile(
        id: 'j${_id++}',
        input: input,
      );
      job.pageCount = 10;
      _queue.add(job);
    }
    notifyListeners();
  }

  @override
  void removeFile(String id) {
    _queue.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  @override
  Future<void> convertAll() async {
    _isRunning = true;
    notifyListeners();
    for (final job in [..._queue]) {
      if (cancelCalled) {
        job.status = JobStatus.cancelled;
        continue;
      }
      job.status = JobStatus.running;
      _page = 0;
      _total = 10;
      _phase = 0;
      job.currentPage = _page;
      job.totalPages = _total;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      _page = 5;
      _phase = 1;
      job.currentPage = _page;
      job.totalPages = _total;
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      if (failAll) {
        job.status = JobStatus.failed;
        job.errorType = 'corrupt';
      } else {
        job.status = JobStatus.done;
      }
      notifyListeners();
    }
    _isRunning = false;
    notifyListeners();
  }

  @override
  void cancel() {
    cancelCalled = true;
    notifyListeners();
  }

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
  // Layout desktop wide (≥900) — panel kiri penuh, aksi terlihat tanpa scroll.
  Future<void> pumpWide(WidgetTester tester, Widget widget) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(widget);
  }

  testWidgets('empty state: drop zone visible (FR-01)', (tester) async {
    await pumpWide(tester, MaterialApp(
      home: HomeScreen(controller: FakeConversionController()),
    ));
    expect(find.byType(DropZone), findsOneWidget);
    expect(find.text('Choose PDF files'), findsOneWidget);
  });

  testWidgets('queue state: file cards + convert all button', (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf'), PdfInput(name: 'b.pdf', path: 'b.pdf')]);
    await tester.pump();

    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);
    expect(find.text('Convert (2)'), findsOneWidget);
  });

  testWidgets('remove file from queue', (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf'), PdfInput(name: 'b.pdf', path: 'b.pdf')]);
    await tester.pump();

    // Hapus 'b.pdf' via tombol remove pertama yang cocok.
    final removeButtons = find.byIcon(Icons.close);
    expect(removeButtons, findsNWidgets(2));
    await tester.tap(removeButtons.last);
    await tester.pump();

    expect(find.text('b.pdf'), findsNothing);
    expect(find.text('Convert (1)'), findsOneWidget);
  });

  testWidgets('running state: progress + file status (FR-08, FR-11)',
      (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf'), PdfInput(name: 'b.pdf', path: 'b.pdf')]);
    await tester.pump();
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));

    expect(find.byType(CircularProgressIndicator), findsWidgets);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    expect(controller.cancelCalled, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    // Setelah batch selesai (cancelled) → summary tampil.
    expect(find.text('Clear all'), findsOneWidget);
  });

  testWidgets('running single file: kartu file tampil sekali (bug fix duplikat)',
      (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
    await tester.pump();
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));

    // Job aktif dirender sekali di kartu "active", bukan dua kali.
    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.byType(FileCard), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  });

  testWidgets('summary state: done files shown, clear resets to empty',
      (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf'), PdfInput(name: 'b.pdf', path: 'b.pdf')]);
    await tester.pump();
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Clear all'), findsOneWidget);
    // FR-09: preview document viewer untuk file yang berhasil.
    expect(find.byType(DocumentViewer), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(DropZone), findsOneWidget);
    expect(controller.queue, isEmpty);
  });

  testWidgets('download: viewer menampilkan dokumen yang dipilih (bug fix)',
      (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
    await tester.pump();
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    // Viewer menampilkan file done (a.md sebagai output name).
    final viewer = tester.widget<DocumentViewer>(find.byType(DocumentViewer));
    expect(viewer.job, isNotNull);
    expect(viewer.job!.input.outputName, 'a.md');
  });

  testWidgets('theme toggle: cycle light → dark → system (M7)', (tester) async {
    final themeController = ThemeController(initial: ThemeMode.light);
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        controller: FakeConversionController(),
        themeController: themeController,
      ),
    ));

    expect(themeController.mode, ThemeMode.light);
    expect(find.byIcon(Icons.light_mode_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.light_mode_outlined));
    await tester.pump();
    expect(themeController.mode, ThemeMode.dark);
    expect(find.byIcon(Icons.dark_mode_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.dark_mode_outlined));
    await tester.pump();
    expect(themeController.mode, ThemeMode.system);
    expect(find.byIcon(Icons.brightness_auto_outlined), findsOneWidget);
  });

  testWidgets('status pill: empty → Ready to process files', (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatusPill(controller: controller)),
    ));

    expect(find.text('Ready to process files'), findsOneWidget);
  });

  testWidgets('status pill: files loaded → "2 files loaded"', (tester) async {
    final controller = FakeConversionController();
    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf'), PdfInput(name: 'b.pdf', path: 'b.pdf')]);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatusPill(controller: controller)),
    ));

    expect(find.text('2 files loaded'), findsOneWidget);
  });

  testWidgets('status pill: running → "Processing 2 documents"',
      (tester) async {
    final controller = FakeConversionController();
    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf'), PdfInput(name: 'b.pdf', path: 'b.pdf')]);
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatusPill(controller: controller)),
    ));

    expect(find.text('Processing 2 documents'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  });

  testWidgets('status pill: selesai → "2 converted"', (tester) async {
    final controller = FakeConversionController();
    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf'), PdfInput(name: 'b.pdf', path: 'b.pdf')]);
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: StatusPill(controller: controller)),
    ));

    expect(find.text('2 converted'), findsOneWidget);
  });

  testWidgets('warning: >10 files → banner muncul (M4)', (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([
      for (var i = 0; i < 11; i++) PdfInput(name: 'f$i.pdf', path: 'f$i.pdf'),
    ]);
    await tester.pump();

    expect(find.textContaining('memory usage will be high'), findsOneWidget);
  });

  testWidgets('warning: file >100 halaman → banner muncul (M4)', (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'big.pdf', path: 'big.pdf')]);
    await tester.pump();
    controller.queue.single.pageCount = 150;
    controller.notifyListeners();
    await tester.pump();

    expect(find.textContaining('150 pages'), findsWidgets);
    // Banner spesifik (pesan lengkap, bukan sekadar metadata kartu).
    expect(
      find.textContaining('large documents may take longer'),
      findsOneWidget,
    );
  });

  testWidgets('warning: batch kecil → tidak ada banner (M4)', (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
    await tester.pump();

    expect(find.textContaining('memory usage will be high'), findsNothing);
    expect(find.textContaining('pages — large documents'), findsNothing);
  });

  testWidgets('progress: kartu running menampilkan bar + metadata (enhance)',
      (tester) async {
    final controller = FakeConversionController();
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
    await tester.pump();
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));

    // Job running: ada LinearProgressIndicator (bar per file).
    expect(find.byType(LinearProgressIndicator), findsWidgets);
    // Metadata progress muncul (fake phase 0 → "Reading"; page 0 of 10).
    expect(find.text('Reading'), findsWidgets);
    expect(find.text('0 of 10 pages · 0%'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
  });

  testWidgets('progress: FileCard indeterminate saat total null (enhance)',
      (tester) async {
    final controller = FakeConversionController();
    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
    controller.queue.single.currentPage = 3;
    controller.queue.single.totalPages = null; // total belum diketahui
    controller.queue.single.status = JobStatus.running;

    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));

    // Running dengan total null → bar indeterminate (default phase 1).
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Converting'), findsOneWidget);
  });
}
