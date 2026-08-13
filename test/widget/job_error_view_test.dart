import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/widgets/job_error_view.dart';

void main() {
  QueuedFile job({String? errorType, String? errorMessage}) => QueuedFile(
        id: '1',
        input: PdfInput(name: 'a.pdf', path: 'C:/a.pdf'),
      )
        ..status = JobStatus.failed
        ..errorType = errorType
        ..errorMessage = errorMessage;

  testWidgets('displays mapped title + full message (wrap, not ellipsis)',
      (tester) async {
    final longMessage = 'Failed to read file: format not recognized. '
        'Check if file is valid or re-convert from source app. '
        'This detailed message is intentionally long to test that text is not truncated.';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: JobErrorView(job: job(
          errorType: 'corrupt',
          errorMessage: longMessage,
        )),
      ),
    ));

    // Mapped title from errorType.
    expect(find.text(Strings.errorCorrupt), findsOneWidget);
    // Full message DISPLAYED (not ellipsis) — full body found.
    expect(find.text(longMessage), findsOneWidget);
  });

  testWidgets('"Show full error" button -> dialog containing full message',
      (tester) async {
    final longMessage = 'Very long error message that exceeds the maximum length '
        'threshold of ninety characters so that the show full error button is displayed.';
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: JobErrorView(job: job(errorType: 'noText', errorMessage: longMessage))),
    ));

    await tester.tap(find.text(Strings.showFullError));
    await tester.pumpAndSettle(); // dialog — safe (not viewer skeleton)

    expect(find.text(longMessage), findsWidgets); // in dialog
    expect(find.byType(SelectableText), findsWidgets);
  });

  testWidgets('without errorMessage -> fallback to title mapping', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: JobErrorView(job: job(errorType: 'encrypted'))),
    ));
    expect(find.text(Strings.errorEncrypted), findsWidgets);
  });

  testWidgets('unknown errorType -> errorGeneric (with %s filled)', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: JobErrorView(job: job(errorType: 'weird'))),
    ));
    // errorGeneric = 'Something went wrong: %s' -> %s replaced with errorType.
    expect(find.text('Something went wrong: weird'), findsOneWidget);
  });
}
