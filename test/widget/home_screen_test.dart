import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/theme/theme_controller.dart';
import 'package:markit/ui/screens/home_screen.dart';
import 'package:markit/ui/widgets/drop_zone.dart';
import 'package:markit/ui/widgets/document_viewer.dart';
import 'package:markit/ui/widgets/file_card.dart';
import 'package:markit/ui/widgets/header/status_pill.dart';

/// Fake controller: simulasi batch tanpa isolate.
class FakeConversionController extends ConversionController {
  final List<QueuedFile> _queue = [];
  bool _isRunning = false;
  int? _page;
  int? _total;
  int _phase = 1;
  bool cancelCalled = false;
  bool failAll = false;

  /// Nama file yang sengaja gagal (errorType 'corrupt').
  final Set<String> failNames = {};

  /// Bila true: convertAll melempar setelah batch (simulasi bug tak terduga).
  bool throwOnConvertAll = false;
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
      if (failAll || failNames.contains(job.fileName)) {
        job.status = JobStatus.failed;
        job.errorType = 'corrupt';
        job.errorMessage ??= 'Simulasi gagal parsing.';
      } else {
        job.status = JobStatus.done;
      }
      notifyListeners();
    }
    if (throwOnConvertAll) {
      throw StateError('boom'); // simulasi bug tak terduga
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

  @override
  Future<void> cleanupTempOutputs() async {}
}

/// Fake platform file_selector: getDirectoryPath mengembalikan [directory].
class _FakeFileSelectorPlatform extends FileSelectorPlatform {
  _FakeFileSelectorPlatform(this.directory);
  final String? directory;

  @override
  Future<String?> getDirectoryPath({
    String? initialDirectory,
    String? confirmButtonText,
  }) async =>
      directory;
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
    expect(find.text('Choose files'), findsOneWidget);
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

  testWidgets('failed job: pesan error tampil lengkap di kartu (bukan ellipsis)',
      (tester) async {
    final controller = FakeConversionController()
      ..failAll = true
      ..addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
    final job = controller.queue.single;
    job.errorType = 'corrupt';
    job.errorMessage = 'Detail error yang cukup panjang untuk memastikan '
        'tidak terpotong oleh ellipsis pada kartu sidebar.';
    await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));
    // runAsync: IO nyata (File.exists / move) macet di fake-async & timer
    // batch berjalan real-time.
    await tester.runAsync(() async {
      await tester.tap(find.text('Convert (1)'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    });
    expect(find.textContaining('tidak terpotong oleh ellipsis'), findsOneWidget);
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

  group('pilih folder output setelah batch (desktop)', () {
    late FileSelectorPlatform original;

    setUp(() {
      original = FileSelectorPlatform.instance;
    });

    tearDown(() {
      FileSelectorPlatform.instance = original;
    });

    // Jalankan interaksi di zone real (runAsync): testWidgets memakai fake
    // async yang TIDAK bisa menyelesaikan IO async dart:io (File.exists,
    // rename, dst.) — tanpa runAsync future-nya macet selamanya di fake queue.
    Future<void> drive(WidgetTester tester, int iterations) =>
        tester.runAsync(() async {
          for (var i = 0; i < iterations; i++) {
            await Future<void>.delayed(const Duration(milliseconds: 50));
            await tester.pump(const Duration(milliseconds: 50));
          }
        });

    testWidgets('batch sukses → tombol Save → pilih folder → .md dipindah',
        (tester) async {
      // Setup pakai IO sinkron — IO async di body testWidgets tidak selesai
      // (continuation menumpuk di fake microtask queue).
      final src = Directory.systemTemp.createTempSync('markit_src');
      final dst = Directory.systemTemp.createTempSync('markit_dst');
      addTearDown(() {
        src.deleteSync(recursive: true);
        dst.deleteSync(recursive: true);
      });

      final controller = FakeConversionController()
        ..addFiles([
          PdfInput(name: 'a.pdf', path: '${src.path}/a.pdf'),
        ]);
      final job = controller.queue.single;
      final oldPath = job.outputPath; // path sebelum dipindah (akan berubah)
      File(job.outputPath).writeAsStringSync('# a'); // simulasi hasil konversi
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(dst.path);

      await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));
      await tester.runAsync(() async {
        await tester.tap(find.text('Convert (1)'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      });
      // Batch (2x10ms) — tanpa auto-dialog lagi setelah selesai.
      await drive(tester, 30);
      // Auto-dialog TIDAK muncul lagi — file belum dipindah sebelum tap Save.
      expect(File('${dst.path}/a.md').existsSync(), isFalse);
      expect(find.text('Save (1)'), findsOneWidget); // tombol muncul

      await tester.runAsync(() async {
        await tester.tap(find.text('Save (1)'));
      });
      // Dialog folder + move + snackbar
      await drive(tester, 10);

      expect(File('${dst.path}/a.md').existsSync(), isTrue);
      expect(File(oldPath).existsSync(), isFalse);
      expect(job.outputPath, '${dst.path}/a.md');
      expect(find.textContaining('Saved 1 file'), findsOneWidget);
    });

    testWidgets('dialog folder di-cancel → output tetap di folder sumber',
        (tester) async {
      final src = Directory.systemTemp.createTempSync('markit_src');
      addTearDown(() {
        src.deleteSync(recursive: true);
      });

      final controller = FakeConversionController()
        ..addFiles([
          PdfInput(name: 'a.pdf', path: '${src.path}/a.pdf'),
        ]);
      final job = controller.queue.single;
      File(job.outputPath).writeAsStringSync('# a');
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(null); // cancel

      await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));
      await tester.runAsync(() async {
        await tester.tap(find.text('Convert (1)'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      });
      await drive(tester, 30);

      // Batch selesai → tombol Save muncul (auto-dialog diganti tombol).
      expect(find.text('Save (1)'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save (1)'));
      });
      await drive(tester, 10);

      expect(File(job.outputPath).existsSync(), isTrue); // tetap di sumber
      expect(job.outputPath, '${src.path}/a.md');
      expect(find.text(Strings.outputNotSaved), findsOneWidget);
    });

    testWidgets('konflik di folder tujuan → dialog overwrite → setuju → diganti',
        (tester) async {
      final src = Directory.systemTemp.createTempSync('markit_src');
      final dst = Directory.systemTemp.createTempSync('markit_dst');
      addTearDown(() {
        src.deleteSync(recursive: true);
        dst.deleteSync(recursive: true);
      });

      final controller = FakeConversionController()
        ..addFiles([
          PdfInput(name: 'a.pdf', path: '${src.path}/a.pdf'),
        ]);
      final job = controller.queue.single;
      File(job.outputPath).writeAsStringSync('# new');
      File('${dst.path}/a.md').writeAsStringSync('# old'); // konflik
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(dst.path);

      await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));
      await tester.runAsync(() async {
        await tester.tap(find.text('Convert (1)'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      });
      await drive(tester, 30);
      // Auto-dialog tidak muncul — file belum dipindah sebelum tap Save.
      expect(File('${dst.path}/a.md').readAsStringSync(), '# old');
      expect(find.text('Save (1)'), findsOneWidget);

      await tester.runAsync(() async {
        await tester.tap(find.text('Save (1)'));
      });
      await drive(tester, 10);
      // Dialog konflik (folder tujuan) muncul → tap tombol overwrite
      expect(find.textContaining('already exist'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text(Strings.overwriteConfirm));
      });
      await drive(tester, 10);

      expect(File('${dst.path}/a.md').readAsStringSync(), '# new');
      expect(job.outputPath, '${dst.path}/a.md');
    });

    testWidgets('tombol Save: muncul saat done>0 & idle; tidak saat running/0 done',
        (tester) async {
      final controller = FakeConversionController();
      await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));
      controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
      await tester.pump();
      expect(find.text('Save (1)'), findsNothing); // belum convert → done=0

      // runAsync: IO nyata (File.exists / move) macet di fake-async.
      await tester.runAsync(() async {
        await tester.tap(find.text('Convert (1)'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      });
      // Batch (2x10ms) selesai → tombol muncul saat idle & done>0.
      await drive(tester, 30);

      expect(find.text('Save (1)'), findsOneWidget); // batch selesai → tombol muncul
    });

    testWidgets('1 gagal 1 sukses → Save hanya memindah yang sukses',
        (tester) async {
      final src = Directory.systemTemp.createTempSync('markit_src');
      final dst = Directory.systemTemp.createTempSync('markit_dst');
      addTearDown(() {
        src.deleteSync(recursive: true);
        dst.deleteSync(recursive: true);
      });

      final controller = FakeConversionController()
        ..failNames.add('bad.pdf')
        ..addFiles([
          PdfInput(name: 'bad.pdf', path: '${src.path}/bad.pdf'),
          PdfInput(name: 'good.pdf', path: '${src.path}/good.pdf'),
        ]);
      final good = controller.queue[1];
      File(good.outputPath).writeAsStringSync('# good'); // hasil konversi
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(dst.path);

      await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));
      await tester.runAsync(() async {
        await tester.tap(find.text('Convert (2)'));
        // Tanpa pump di sini: frame saat kartu running meluap di font test
        // (Ahem, 29px) bila batch 2-job belum selesai. Batch selesai dalam
        // ~40ms real — tunggu real-time di bawah, lalu pump.
        await Future<void>.delayed(const Duration(milliseconds: 150));
      });
      // Tunggu batch selesai di real time SEBELUM pump apa pun — progress
      // row FileCard meluap di font test (Ahem) bila frame di-pump saat
      // kartu running phase converting.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();
      await drive(tester, 40);
      // Batch selesai: 1 failed, 1 done → tombol Save (1).
      expect(find.text('Save (1)'), findsOneWidget);
      await tester.runAsync(() async {
        await tester.tap(find.text('Save (1)'));
      });
      await drive(tester, 10);

      expect(File('${dst.path}/good.md').existsSync(), isTrue);
      expect(File('${dst.path}/bad.md').existsSync(), isFalse); // failed tidak ikut
      expect(good.outputPath, '${dst.path}/good.md');
    });

    testWidgets('convertAll throw → save tetap ditawarkan (finally)',
        (tester) async {
      final src = Directory.systemTemp.createTempSync('markit_src');
      final dst = Directory.systemTemp.createTempSync('markit_dst');
      addTearDown(() {
        src.deleteSync(recursive: true);
        dst.deleteSync(recursive: true);
      });

      final controller = FakeConversionController()..throwOnConvertAll = true;
      controller.addFiles([
        PdfInput(name: 'a.pdf', path: '${src.path}/a.pdf'),
      ]);
      final job = controller.queue.single;
      File(job.outputPath).writeAsStringSync('# a'); // hasil konversi
      FileSelectorPlatform.instance = _FakeFileSelectorPlatform(dst.path);

      await pumpWide(tester, MaterialApp(home: HomeScreen(controller: controller)));
      await tester.runAsync(() async {
        await tester.tap(find.text('Convert (1)'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      });
      // Tunggu batch selesai (dan finally menawarkan save) di real time
      // SEBELUM pump — progress row FileCard meluap di font test (Ahem)
      // bila frame di-pump saat kartu running phase converting.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump();

      // convertAll melempar → _convertAll menangkap di catch, tapi finally
      // tetap menawarkan save → file sukses tetap dipindah.
      expect(File('${dst.path}/a.md').existsSync(), isTrue);
      expect(job.outputPath, '${dst.path}/a.md');
    });
  });
}
