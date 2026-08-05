import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/isolate/conversion_controller.dart';
import 'package:pdflow/ui/screens/home_screen.dart';
import 'package:pdflow/ui/widgets/drop_zone.dart';
import 'package:pdflow/ui/widgets/progress_panel.dart';

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
  void addFiles(List<String> paths) {
    for (final path in paths) {
      final job = QueuedFile(
        id: 'j${_id++}',
        pdfPath: path,
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
      notifyListeners();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      _page = 5;
      _phase = 1;
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
}

void main() {
  testWidgets('empty state: drop zone visible (FR-01)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: FakeConversionController()),
    ));
    expect(find.byType(DropZone), findsOneWidget);
    expect(find.text('Choose PDF files'), findsOneWidget);
    expect(find.byType(ProgressPanel), findsNothing);
  });

  testWidgets('queue state: file cards + convert all button', (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.addFiles(['a.pdf', 'b.pdf']);
    await tester.pump();

    expect(find.text('a.pdf'), findsOneWidget);
    expect(find.text('b.pdf'), findsOneWidget);
    expect(find.text('Convert all (2)'), findsOneWidget);
  });

  testWidgets('remove file from queue', (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.addFiles(['a.pdf', 'b.pdf']);
    await tester.pump();

    // Hapus 'b.pdf' via tombol remove pertama yang cocok.
    final removeButtons = find.byIcon(Icons.close);
    expect(removeButtons, findsNWidgets(2));
    await tester.tap(removeButtons.last);
    await tester.pump();

    expect(find.text('b.pdf'), findsNothing);
    expect(find.text('Convert all (1)'), findsOneWidget);
  });

  testWidgets('running state: progress + file status (FR-08, FR-11)',
      (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.addFiles(['a.pdf', 'b.pdf']);
    await tester.pump();
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));

    expect(find.byType(ProgressPanel), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    expect(controller.cancelCalled, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    // Setelah batch selesai (cancelled) → summary tampil.
    expect(find.text('Clear all'), findsOneWidget);
  });

  testWidgets('summary state: done files shown, clear resets to empty',
      (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.addFiles(['a.pdf', 'b.pdf']);
    await tester.pump();
    controller.convertAll();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.text('Clear all'), findsOneWidget);

    await tester.tap(find.text('Clear all'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(DropZone), findsOneWidget);
    expect(controller.queue, isEmpty);
  });
}
