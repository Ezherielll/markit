import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/theme/markit_theme.dart';
import 'package:markit/ui/widgets/document_viewer.dart';

/// Done job with .md output on disk (desktop) — ready for display.
(Directory, QueuedFile) _doneJob() {
  final tmp = Directory.systemTemp.createTempSync('markit_perf_dv');
  addTearDown(() {
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // Windows: file locked briefly — ignore.
    }
  });
  const md = '# Heading\n\nbody\n';
  File('${tmp.path}/doc.md').writeAsStringSync(md);
  final job = QueuedFile(
    id: 'j1',
    input: PdfInput(
      name: 'doc.md',
      path: '${tmp.path}/doc.md',
      format: InputFormat.word,
    ),
    status: JobStatus.done,
  )..content = md;
  return (tmp, job);
}

/// Root app with theme [theme] and intentionally rebuilding parent.
Widget app(QueuedFile job, ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Builder(
      builder: (context) => _RebuildingParent(job: job),
    ),
  ),
);

/// Pump root + wait for `_load` I/O completion (reading output file on disk).
Future<void> pumpLoaded(WidgetTester tester, Widget root) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(root);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
  });
}

const int heavyChars = 24 * 1024;

QueuedFile _heavyDoneJob(String mdPath, String md) => QueuedFile(
      id: 'heavy',
      input: PdfInput(
        name: 'heavy.md',
        path: mdPath,
        format: InputFormat.word,
      ),
      status: JobStatus.done,
    )..content = md;

void main() {
  testWidgets('cached paper: parent rebuild does not create new MarkdownBody',
      (tester) async {
    final (_, job) = _doneJob();

    await pumpLoaded(tester, app(job, MarkitTheme.light()));

    final first = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    for (var i = 0; i < 10; i++) {
      // Parent intentionally rebuilt; build produces new DocumentViewer
      // instance (similar to HomeScreen rebuilding every frame during conversion).
      await tester.pumpWidget(app(job, MarkitTheme.light()));
    }

    final after = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(identical(after, first), isTrue,
        reason: 'paper subtree must be cached, not rebuilt');
  });

  testWidgets('theme toggle: paper cache invalid — new MarkdownBody',
      (tester) async {
    final (_, job) = _doneJob();

    await pumpLoaded(tester, app(job, MarkitTheme.light()));
    final light = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    // Toggle to dark (DocumentViewer state preserved — job unchanged).
    await tester.pumpWidget(app(job, MarkitTheme.dark()));
    // MaterialApp uses AnimatedTheme (200 ms) — wait for animation to complete
    // so Theme.of(context) actually returns new brightness.
    await tester.pump(const Duration(milliseconds: 300));

    final dark = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(identical(dark, light), isFalse,
        reason: 'theme change must rebuild paper (colors follow theme)');
  });

  testWidgets('heavy content: spinner displayed first, then rendered content',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('markit_perf_heavy');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // ignore
      }
    });
    final md = '# Judul\n\n${'paragraf dengan kata-kata panjang\n' * 2000}';
    File('${tmp.path}/heavy.md').writeAsStringSync(md);
    final job = _heavyDoneJob('${tmp.path}/heavy.md', md);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: MarkitTheme.light(),
        home: Scaffold(body: DocumentViewer(job: job)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    // First frame after load: spinner renders.
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Next frame: content rendered.
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(MarkdownBody), findsOneWidget);
  });

  testWidgets('light content: no spinner, rendered immediately', (tester) async {
    final tmp = Directory.systemTemp.createTempSync('markit_perf_light');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // ignore
      }
    });
    const md = '# Judul\n\nIsi.\n';
    File('${tmp.path}/light.md').writeAsStringSync(md);
    final job = _heavyDoneJob('${tmp.path}/light.md', md);

    await tester.runAsync(() async {
      await tester.pumpWidget(MaterialApp(
        theme: MarkitTheme.light(),
        home: Scaffold(body: DocumentViewer(job: job)),
      ));
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });

    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(MarkdownBody), findsOneWidget);
  });
}

class _RebuildingParent extends StatefulWidget {
  const _RebuildingParent({required this.job});
  final QueuedFile job;

  @override
  State<_RebuildingParent> createState() => _RebuildingParentState();
}

class _RebuildingParentState extends State<_RebuildingParent> {
  @override
  Widget build(BuildContext context) {
    return DocumentViewer(job: widget.job);
  }
}
