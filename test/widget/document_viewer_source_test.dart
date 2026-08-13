import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/source/text_source_view.dart';
import 'package:markit/ui/theme/markit_theme.dart';
import 'package:markit/ui/widgets/document_viewer.dart';

import '../helpers/docx_factory.dart';

QueuedFile _job(
  String name,
  InputFormat format, {
  String? path,
  Uint8List? bytes,
  JobStatus status = JobStatus.queued,
  String? content,
}) =>
    QueuedFile(
      id: name,
      input: PdfInput(name: name, path: path, bytes: bytes, format: format),
      status: status,
    )..content = content;

Future<void> _pump(WidgetTester tester, QueuedFile job) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      theme: MarkitTheme.light(),
      home: Scaffold(body: DocumentViewer(job: job)),
    ));
    // Real time so I/O (reading source/output file) completes in original zone.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
  });
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_dv_test');
  });

  tearDown(() async {
    for (var i = 0; i < 5; i++) {
      try {
        await tmp.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  testWidgets('queued CSV: automatic Source mode, raw source text displayed',
      (tester) async {
    File('${tmp.path}/notes.csv').writeAsStringSync('lorem\nipsum\n');
    final job = _job(
      'notes.csv',
      InputFormat.csv,
      path: '${tmp.path}/notes.csv',
      status: JobStatus.queued,
    );

    await _pump(tester, job);

    expect(find.byType(TextSourceView), findsOneWidget);
    expect(find.text('lorem\nipsum\n'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
    // Two-segment toolbar.
    expect(find.text(Strings.showSource), findsOneWidget);
    expect(find.text(Strings.showOutput), findsOneWidget);
  });

  testWidgets('queued DOCX (zip): tag-stripped text preview displayed',
      (tester) async {
    final docx = buildTestDocx(
      documentXml: docxDocument(
        '${docxParagraph(docxRun('Judul dokumen'))}'
        '${docxParagraph(docxRun('Isi paragraf.'))}',
      ),
    );
    final job = _job(
      'notes.docx',
      InputFormat.word,
      bytes: docx,
      status: JobStatus.queued,
    );

    await _pump(tester, job);

    expect(find.byType(TextSourceView), findsOneWidget);
    expect(find.textContaining('Judul dokumen'), findsOneWidget);
  });

  testWidgets('queued CSV: toggle to Output -> skeleton (no output yet)',
      (tester) async {
    File('${tmp.path}/notes.csv').writeAsStringSync('lorem\n');
    final job = _job(
      'notes.csv',
      InputFormat.csv,
      path: '${tmp.path}/notes.csv',
      status: JobStatus.queued,
    );

    await _pump(tester, job);
    await tester.tap(find.text(Strings.showOutput));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TextSourceView), findsNothing);
  });

  testWidgets('running: source displayed (no output yet)', (tester) async {
    File('${tmp.path}/notes.csv').writeAsStringSync('lorem\n');
    final job = _job(
      'notes.csv',
      InputFormat.csv,
      path: '${tmp.path}/notes.csv',
      status: JobStatus.running,
    );

    await _pump(tester, job);

    expect(find.byType(TextSourceView), findsOneWidget);
    expect(find.text('lorem\n'), findsOneWidget);
  });

  testWidgets('legacy format: formatNotSupported message displayed', (tester) async {
    final job = _job('a.doc', InputFormat.word, status: JobStatus.queued);

    await _pump(tester, job);

    expect(find.text(Strings.formatNotSupported), findsOneWidget);
  });

  testWidgets('missing source file: sourceLoadFailed message displayed',
      (tester) async {
    final job = _job(
      'ghost.csv',
      InputFormat.csv,
      path: '${tmp.path}/ghost.csv',
      status: JobStatus.queued,
    );

    await _pump(tester, job);

    expect(find.text(Strings.sourceLoadFailed), findsOneWidget);
  });

  testWidgets('done: Output mode default (rendered); toggle Source<->Output',
      (tester) async {
    const md = '# Heading\n\nbody\n';
    File('${tmp.path}/doc.csv').writeAsStringSync(md);
    File('${tmp.path}/doc.md').writeAsStringSync(md);
    final job = _job(
      'doc.csv',
      InputFormat.csv,
      path: '${tmp.path}/doc.csv',
      status: JobStatus.done,
      content: md,
    );

    await _pump(tester, job);

    // Default rendered output — Rendered|Raw toggle also displayed.
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text(Strings.showRendered), findsOneWidget);

    // Switch to Source.
    await tester.tap(find.text(Strings.showSource));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TextSourceView), findsOneWidget);
    expect(find.text('# Heading\n\nbody\n'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);

    // Return to Output.
    await tester.tap(find.text(Strings.showOutput));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('raw view (output): Scrollbar does not throw assertion (bug #2)',
      (tester) async {
    final job = _job(
      'doc.csv',
      InputFormat.csv,
      path: '${tmp.path}/doc.csv',
      status: JobStatus.done,
      // Long enough -> horizontal scroll active in raw view.
      content: '${'kata ' * 400}\n',
    );

    await _pump(tester, job);

    // Toggle raw view — horizontal Scrollbar without explicit controller
    // throws "Scrollbar has no ScrollPosition" in scheduler callback.
    await tester.tap(find.text(Strings.showRaw));
    await tester.pump(const Duration(milliseconds: 100));
    // Several more frames: assertion appears in next frame callback.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('failed but readable source: raw text still displayed', (tester) async {
    File('${tmp.path}/bad.csv').writeAsStringSync('konten mentah\n');
    final job = _job(
      'bad.csv',
      InputFormat.csv,
      path: '${tmp.path}/bad.csv',
      status: JobStatus.failed,
    );

    await _pump(tester, job);

    expect(find.text('konten mentah\n'), findsOneWidget);
    expect(find.text(Strings.sourceLoadFailed), findsNothing);
  });

  testWidgets('failed and unreadable source: sourceLoadFailed',
      (tester) async {
    final job = _job(
      'gone.csv',
      InputFormat.csv,
      path: '${tmp.path}/gone.csv',
      status: JobStatus.failed,
    );

    await _pump(tester, job);

    expect(find.text(Strings.sourceLoadFailed), findsOneWidget);
  });
}
