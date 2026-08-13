import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/theme/markit_theme.dart';
import 'package:markit/ui/widgets/document_viewer.dart';

void main() {
  testWidgets('paper di-cache: rebuild parent tidak membuat MarkdownBody baru',
      (tester) async {
    final tmp = Directory.systemTemp.createTempSync('markit_perf_dv');
    addTearDown(() {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        // Windows: file terkunci sesaat — abaikan.
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

    Widget app(QueuedFile job) => MaterialApp(
      theme: PdflowTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => _RebuildingParent(job: job),
        ),
      ),
    );

    await tester.runAsync(() async {
      await tester.pumpWidget(app(job));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await tester.pump();
    });

    final first = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    for (var i = 0; i < 10; i++) {
      // Parent sengaja di-rebuild ulang; build menghasilkan instance
      // DocumentViewer baru (mirip HomeScreen yang rebuild tiap frame saat
      // konversi berjalan).
      await tester.pumpWidget(app(job));
    }

    final after = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(identical(after, first), isTrue,
        reason: 'subtree paper harus di-cache, bukan di-build ulang');
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
