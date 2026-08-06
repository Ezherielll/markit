import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:irondash_message_channel/irondash_message_channel.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/screens/about_screen.dart';
import 'package:markit/ui/screens/home_screen.dart';
import 'package:markit/ui/theme/markit_theme.dart';
// ignore: implementation_imports
import 'package:super_native_extensions/src/native/context.dart' as sne;

/// Fake controller selesai-siap: file langsung done + content md.
class ShotController extends ConversionController {
  final List<QueuedFile> _queue = [];

  @override
  bool get isRunning => false;

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
  int get completedCount => _queue.length;

  @override
  int get doneCount => _queue.length;

  @override
  void addFiles(List<PdfInput> inputs) {
    for (final input in inputs) {
      final job = QueuedFile(
        id: 'shot${_queue.length}',
        input: input,
        status: JobStatus.done,
      );
      job.pageCount = 12;
      job.content = 'shot-content';
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

Future<void> _loadFonts() async {
  for (final (family, asset) in [
    ('Fraunces', 'assets/fonts/Fraunces.ttf'),
    ('Inter', 'assets/fonts/Inter.ttf'),
    ('JetBrainsMono', 'assets/fonts/JetBrainsMono.ttf'),
  ]) {
    final bytes = File(asset).readAsBytesSync();
    final loader = FontLoader(family)
      ..addFont(Future.value(ByteData.sublistView(bytes)));
    await loader.load();
  }
}

Future<void> _pumpApp(
  WidgetTester tester,
  Widget home, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: PdflowTheme.light(),
    home: home,
  ));
  await tester.pumpAndSettle();
}

void main() {
  // super_drag_and_drop (DropRegion) butuh plugin native via irondash
  // engine context — di widget test tidak ada; stub channel-nya.
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.irondash.engine_context'),
      (call) async => 1,
    );
    final mock = MockMessageChannelContext()
      ..registerMockMethodCallHandler('DropManager', (call) async => null)
      ..registerMockMethodCallHandler('DragManager', (call) async => null);
    sne.setContextOverride(mock);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('dev.irondash.engine_context'),
      null,
    );
  });

  testWidgets('golden: empty state', (tester) async {
    await _loadFonts();
    await _pumpApp(tester, HomeScreen(controller: ShotController()));
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/empty.png'),
    );
  });

  testWidgets('golden: hasil konversi (done)', (tester) async {
    await _loadFonts();
    final controller = ShotController();
    final tmp = Directory.systemTemp.createTempSync('markit_shot_golden');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final pdf = '${tmp.path}/sample.pdf';
    final md = '${tmp.path}/sample.md';
    File(md).writeAsStringSync(
      '# The Quick Brown Fox\n\n'
      'This is the first paragraph of the converted document. It shows how '
      'headings, paragraphs and lists come out as clean, structured '
      'Markdown — ready to read or feed to AI tools.\n\n'
      '## Features\n\n'
      '- Fast, local conversion\n'
      '- 100% offline & private\n'
      '- Batch processing with ZIP download\n\n'
      '## Overview table\n\n'
      '| Format | Status |\n'
      '| --- | --- |\n'
      '| PDF | Supported |\n'
      '| DOCX | Roadmap |\n'
      '| CSV | Supported |\n',
    );
    controller.addFiles([PdfInput(name: 'sample.pdf', path: pdf)]);
    controller.queue.single
      ..content = null
      ..failedPages = const [];
    await _pumpApp(tester, HomeScreen(controller: controller));
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/done.png'),
    );
  });

  testWidgets('golden: halaman about', (tester) async {
    await _loadFonts();
    await _pumpApp(tester, const AboutScreen());
    expect(find.text(Strings.aboutTitle), findsOneWidget);
    await expectLater(
      find.byType(AboutScreen),
      matchesGoldenFile('goldens/about.png'),
    );
  });
}
