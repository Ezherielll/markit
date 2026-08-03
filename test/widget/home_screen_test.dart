import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/isolate/conversion_controller.dart';
import 'package:pdflow/ui/screens/home_screen.dart';
import 'package:pdflow/ui/widgets/drop_zone.dart';
import 'package:pdflow/ui/widgets/progress_panel.dart';
import 'package:pdflow/ui/widgets/result_panel.dart';

/// Fake controller: simulasi konversi tanpa isolate.
class FakeConversionController extends ConversionController {
  bool _isRunning = false;
  int? _page;
  int? _total;
  int _phase = 1;
  String? _out;
  String? _errType;
  String? _errMsg;
  List<int> _failedPages = const [];
  double? _bodyFontSize;
  bool cancelCalled = false;
  bool fail = false;

  @override
  bool get isRunning => _isRunning;

  @override
  int? get currentPage => _page;

  @override
  int? get totalPages => _total;

  @override
  int get phase => _phase;

  @override
  String? get outputPath => _out;

  @override
  List<int> get failedPages => _failedPages;

  @override
  double? get bodyFontSize => _bodyFontSize;

  @override
  String? get errorType => _errType;

  @override
  String? get errorMessage => _errMsg;

  @override
  Future<void> convert({
    required String pdfPath,
    required String outputPath,
  }) async {
    _isRunning = true;
    _page = 0;
    _total = 10;
    _phase = 0;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _page = 5;
    _phase = 1;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (fail) {
      _errType = 'corrupt';
      _errMsg = 'Corrupt file';
    } else {
      _out = outputPath;
      _failedPages = const [3];
    }
    _isRunning = false;
    notifyListeners();
  }

  @override
  void cancel() {
    cancelCalled = true;
  }

  @override
  void reset() {
    _out = null;
    _errType = null;
    _errMsg = null;
    _failedPages = const [];
    _bodyFontSize = null;
    notifyListeners();
  }
}

void main() {
  testWidgets('empty state: drop zone + pick button visible (FR-01)',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: FakeConversionController()),
    ));
    expect(find.byType(DropZone), findsOneWidget);
    expect(find.text('Choose a PDF file'), findsOneWidget);
    expect(find.byType(ProgressPanel), findsNothing);
  });

  testWidgets('error state: message shown, no crash (FR-10)', (tester) async {
    final controller = FakeConversionController()..fail = true;
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.convert(pdfPath: 'x.pdf', outputPath: 'x.md');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(
      find.textContaining('Could not open the PDF'),
      findsOneWidget,
    );
  });

  testWidgets('done state: result panel rendered (FR-09)', (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.convert(pdfPath: 'x.pdf', outputPath: 'x.md');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();

    expect(find.byType(ResultPanel), findsOneWidget);
    expect(find.text('x.md'), findsOneWidget);
  });

  testWidgets('convert another: reset kembali ke empty state', (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.convert(pdfPath: 'x.pdf', outputPath: 'x.md');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byType(ResultPanel), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Convert another'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('Convert another'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350)); // AnimatedSwitcher

    expect(find.byType(ResultPanel), findsNothing);
    expect(find.byType(DropZone), findsOneWidget);
    expect(controller.outputPath, isNull);
  });

  testWidgets('running state: progress panel + cancel button (FR-08, FR-11)',
      (tester) async {
    final controller = FakeConversionController();
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(controller: controller),
    ));

    controller.convert(pdfPath: 'x.pdf', outputPath: 'x.md');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));

    expect(find.byType(ProgressPanel), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    expect(controller.cancelCalled, isTrue);

    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.text('x.md'), findsOneWidget);
  });
}
