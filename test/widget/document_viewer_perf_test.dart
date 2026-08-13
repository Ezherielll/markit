import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/theme/markit_theme.dart';
import 'package:markit/ui/widgets/document_viewer.dart';

/// Job done dengan output .md di disk (desktop) — siap ditampilkan.
(Directory, QueuedFile) _doneJob() {
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
  return (tmp, job);
}

/// Root app dengan tema [theme] dan parent yang sengaja di-rebuild.
Widget app(QueuedFile job, ThemeData theme) => MaterialApp(
  theme: theme,
  home: Scaffold(
    body: Builder(
      builder: (context) => _RebuildingParent(job: job),
    ),
  ),
);

/// Pump root + tunggu I/O `_load` selesai (baca file output di disk).
Future<void> pumpLoaded(WidgetTester tester, Widget root) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(root);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await tester.pump();
  });
}

void main() {
  testWidgets('paper di-cache: rebuild parent tidak membuat MarkdownBody baru',
      (tester) async {
    final (_, job) = _doneJob();

    await pumpLoaded(tester, app(job, PdflowTheme.light()));

    final first = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    for (var i = 0; i < 10; i++) {
      // Parent sengaja di-rebuild ulang; build menghasilkan instance
      // DocumentViewer baru (mirip HomeScreen yang rebuild tiap frame saat
      // konversi berjalan).
      await tester.pumpWidget(app(job, PdflowTheme.light()));
    }

    final after = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(identical(after, first), isTrue,
        reason: 'subtree paper harus di-cache, bukan di-build ulang');
  });

  testWidgets('toggle tema: cache paper invalid — MarkdownBody baru',
      (tester) async {
    final (_, job) = _doneJob();

    await pumpLoaded(tester, app(job, PdflowTheme.light()));
    final light = tester.widget<MarkdownBody>(find.byType(MarkdownBody));

    // Toggle ke dark (state DocumentViewer dipertahankan — job tidak berubah).
    await tester.pumpWidget(app(job, PdflowTheme.dark()));
    // MaterialApp memakai AnimatedTheme (200 ms) — tunggu animasi selesai
    // agar Theme.of(context) benar-benar mengembalikan brightness baru.
    await tester.pump(const Duration(milliseconds: 300));

    final dark = tester.widget<MarkdownBody>(find.byType(MarkdownBody));
    expect(identical(dark, light), isFalse,
        reason: 'ganti tema harus membangun ulang paper (warna ikut tema)');
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
