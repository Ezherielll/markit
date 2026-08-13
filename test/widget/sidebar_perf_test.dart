import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/isolate/conversion_executor.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/theme/markit_theme.dart';
import 'package:markit/ui/widgets/file_card.dart';
import 'package:markit/ui/widgets/left_panel.dart';

class _NoopExecutor implements ConversionExecutor {
  @override
  Future<void> initialize() async {}
  @override
  Future<JobExecutionResult> runJob({
    required String jobId,
    required String pdfPath,
    Uint8List? pdfBytes,
    required String outputPath,
    InputFormat format = InputFormat.pdf,
    void Function(int page, int total, int phase, int elapsedMs)? onProgress,
  }) async =>
      JobExecutionResult(
        success: true,
        pageCount: 1,
        failedPages: const [],
        bodyFontSize: 0,
        outputPath: outputPath,
        content: '',
      );
  @override
  void cancel() {}
  @override
  void resetCancel() {}
  @override
  Future<void> shutdown() async {}
}

Widget _wrap(ConversionController controller) => MaterialApp(
      theme: MarkitTheme.light(),
      home: Scaffold(
        body: SizedBox(
          height: 600,
          child: LeftPanel(
            controller: controller,
            onAddMore: () {},
            onConvertAll: () {},
            onClear: () {},
            onRemove: (_) {},
            onSelect: (_) {},
            onDownloadFile: (_) {},
            onSaveOutput: () {},
          ),
        ),
      ),
    );

void main() {
  testWidgets('large batch: only visible cards are built (lazy)',
      (tester) async {
    final controller = BatchConversionController(executor: _NoopExecutor());
    controller.addFiles([
      for (var i = 0; i < 60; i++)
        PdfInput(name: 'f$i.csv', format: InputFormat.csv),
    ]);

    await tester.pumpWidget(_wrap(controller));
    await tester.pump();

    final built = find.byType(FileCard).evaluate().length;
    expect(built, lessThan(60));
    expect(built, greaterThan(0));
    // Action footer still exists — scroll down first: list items built lazily,
    // so footer doesn't exist before approaching viewport.
    await tester.scrollUntilVisible(
      find.text('Add files'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Add files'), findsWidgets);
  });
}
