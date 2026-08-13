import 'dart:io';

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

QueuedFile _job(
  String name,
  InputFormat format, {
  String? path,
  JobStatus status = JobStatus.queued,
  String? content,
}) =>
    QueuedFile(
      id: name,
      input: PdfInput(name: name, path: path, format: format),
      status: status,
    )..content = content;

Future<void> _pump(WidgetTester tester, QueuedFile job) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(MaterialApp(
      theme: PdflowTheme.light(),
      home: Scaffold(body: DocumentViewer(job: job)),
    ));
    // Waktu nyata agar I/O (baca file sumber/output) selesai di zone asli.
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

  testWidgets('queued TXT: mode Source otomatis, teks sumber tampil',
      (tester) async {
    File('${tmp.path}/notes.txt').writeAsStringSync('lorem\nipsum\n');
    final job = _job(
      'notes.txt',
      InputFormat.text,
      path: '${tmp.path}/notes.txt',
      status: JobStatus.queued,
    );

    await _pump(tester, job);

    expect(find.byType(TextSourceView), findsOneWidget);
    expect(find.text('lorem\nipsum\n'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);
    // Toolbar dua segmen.
    expect(find.text(Strings.showSource), findsOneWidget);
    expect(find.text(Strings.showOutput), findsOneWidget);
  });

  testWidgets('queued TXT: toggle ke Output → skeleton (belum ada hasil)',
      (tester) async {
    File('${tmp.path}/notes.txt').writeAsStringSync('lorem\n');
    final job = _job(
      'notes.txt',
      InputFormat.text,
      path: '${tmp.path}/notes.txt',
      status: JobStatus.queued,
    );

    await _pump(tester, job);
    await tester.tap(find.text(Strings.showOutput));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(TextSourceView), findsNothing);
  });

  testWidgets('running: sumber tampil (hasil belum ada)', (tester) async {
    File('${tmp.path}/notes.txt').writeAsStringSync('lorem\n');
    final job = _job(
      'notes.txt',
      InputFormat.text,
      path: '${tmp.path}/notes.txt',
      status: JobStatus.running,
    );

    await _pump(tester, job);

    expect(find.byType(TextSourceView), findsOneWidget);
    expect(find.text('lorem\n'), findsOneWidget);
  });

  testWidgets('format belum didukung: pesan formatNotSupported tampil',
      (tester) async {
    final job = _job('a.zip', InputFormat.zip, status: JobStatus.queued);

    await _pump(tester, job);

    expect(find.text(Strings.formatNotSupported), findsOneWidget);
  });

  testWidgets('file sumber hilang: pesan sourceLoadFailed tampil',
      (tester) async {
    final job = _job(
      'ghost.txt',
      InputFormat.text,
      path: '${tmp.path}/ghost.txt',
      status: JobStatus.queued,
    );

    await _pump(tester, job);

    expect(find.text(Strings.sourceLoadFailed), findsOneWidget);
  });

  testWidgets('done: mode Output default (rendered); toggle Source↔Output',
      (tester) async {
    const md = '# Heading\n\nbody\n';
    File('${tmp.path}/doc.txt').writeAsStringSync(md);
    File('${tmp.path}/doc.md').writeAsStringSync(md);
    final job = _job(
      'doc.txt',
      InputFormat.text,
      path: '${tmp.path}/doc.txt',
      status: JobStatus.done,
      content: md,
    );

    await _pump(tester, job);

    // Output rendered default — toggle Rendered|Raw ikut tampil.
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.text(Strings.showRendered), findsOneWidget);

    // Pindah ke Source.
    await tester.tap(find.text(Strings.showSource));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TextSourceView), findsOneWidget);
    expect(find.text('# Heading\n\nbody\n'), findsOneWidget);
    expect(find.byType(MarkdownBody), findsNothing);

    // Kembali ke Output.
    await tester.tap(find.text(Strings.showOutput));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('raw view (output): Scrollbar tidak melempar assertion (bug #2)',
      (tester) async {
    final job = _job(
      'doc.txt',
      InputFormat.text,
      path: '${tmp.path}/doc.txt',
      status: JobStatus.done,
      // Cukup panjang → scroll horizontal aktif pada raw view.
      content: '${'kata ' * 400}\n',
    );

    await _pump(tester, job);

    // Toggle raw view — Scrollbar horizontal tanpa controller eksplisit
    // melempar "Scrollbar has no ScrollPosition" di scheduler callback.
    await tester.tap(find.text(Strings.showRaw));
    await tester.pump(const Duration(milliseconds: 100));
    // Beberapa frame lagi: assertion muncul di frame callback berikutnya.
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tester.takeException(), isNull);
  });

  testWidgets('failed tapi sumber terbaca: teks tetap tampil', (tester) async {
    File('${tmp.path}/bad.txt').writeAsStringSync('konten mentah\n');
    final job = _job(
      'bad.txt',
      InputFormat.text,
      path: '${tmp.path}/bad.txt',
      status: JobStatus.failed,
    );

    await _pump(tester, job);

    expect(find.text('konten mentah\n'), findsOneWidget);
    expect(find.text(Strings.sourceLoadFailed), findsNothing);
  });

  testWidgets('failed dan sumber tidak terbaca: sourceLoadFailed',
      (tester) async {
    final job = _job(
      'gone.txt',
      InputFormat.text,
      path: '${tmp.path}/gone.txt',
      status: JobStatus.failed,
    );

    await _pump(tester, job);

    expect(find.text(Strings.sourceLoadFailed), findsOneWidget);
  });
}
