import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/screens/about_screen.dart';
import 'package:markit/ui/screens/home_screen.dart';

class FakeController extends ConversionController {
  final List<QueuedFile> _queue = [];
  final bool _running = false;

  @override
  bool get isRunning => _running;

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

  @override
  void addFiles(List<PdfInput> inputs) {
    for (final input in inputs) {
      _queue.add(QueuedFile(id: 'j${_queue.length}', input: input));
    }
    notifyListeners();
  }

  @override
  void removeFile(String id) {
    _queue.removeWhere((f) => f.id == id);
    notifyListeners();
  }

  @override
  Future<void> convertAll() async {}

  @override
  void cancel() {}

  @override
  void reset() {
    _queue.clear();
    notifyListeners();
  }

  @override
  Future<void> shutdown() async {}
}

Future<void> pumpHome(WidgetTester tester, FakeController controller) async {
  tester.view.physicalSize = const Size(1280, 800);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: HomeScreen(controller: controller),
  ));
}

void main() {
  testWidgets('header: tap brand lockup → reset ke halaman utama', (tester) async {
    final controller = FakeController();
    controller.addFiles([PdfInput(name: 'a.pdf', path: 'a.pdf')]);
    await pumpHome(tester, controller);
    await tester.pump();

    expect(find.text('a.pdf'), findsOneWidget);

    await tester.tap(find.text(Strings.appTitle));
    await tester.pumpAndSettle();

    expect(controller.queue, isEmpty);
    expect(find.text('a.pdf'), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('header: tap icon about → AboutScreen tampil, back kembali',
      (tester) async {
    final controller = FakeController();
    await pumpHome(tester, controller);

    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsOneWidget);
    expect(find.text(Strings.aboutTitle), findsOneWidget);

    await tester.tap(find.byIcon(Icons.arrow_back));
    await tester.pumpAndSettle();

    expect(find.byType(AboutScreen), findsNothing);
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('about: render tanpa exception, konten utama tampil', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AboutScreen()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(Strings.aboutIntro), findsOneWidget);
    expect(find.text(Strings.aboutHowTitle), findsOneWidget);
    expect(find.text(Strings.aboutPrivacyTitle), findsWidgets);
    expect(find.text(Strings.aboutFaqTitle), findsOneWidget);
    expect(find.text(Strings.aboutFaq1Q), findsOneWidget);
  });
}
