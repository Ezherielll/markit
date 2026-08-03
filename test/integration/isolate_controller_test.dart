import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/isolate/conversion_controller.dart';

import '../helpers/pdf_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdflow_iso_test');
  });
  tearDown(() async {
    // Isolate worker mungkin masih melepas handle file — retry beberapa kali.
    for (var i = 0; i < 5; i++) {
      try {
        await tmp.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  test('isolate: convert PDF → markdown via worker (FR-08)', () async {
    final pdfPath = '${tmp.path}/book.pdf';
    File(pdfPath).writeAsBytesSync(buildTestPdf());
    final outPath = '${tmp.path}/book.md';

    final controller = IsolateConversionController();
    final progress = <int>[];
    controller.addListener(() {
      if (controller.currentPage != null) progress.add(controller.currentPage!);
    });

    await controller.convert(pdfPath: pdfPath, outputPath: outPath);

    // Tunggu selesai (worker async) dengan timeout.
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (controller.isRunning && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(controller.isRunning, isFalse);
    expect(controller.errorType, isNull);
    expect(controller.outputPath, outPath);
    expect(File(outPath).existsSync(), isTrue);

    final md = File(outPath).readAsStringSync();
    expect(md, contains('# The Quick Brown Fox'));
    expect(md, contains('# Chapter Two'));
    expect(md, contains('- Item one'));
    controller.dispose();
  });

  test('isolate: error corrupt → errorType corrupt (FR-10a)', () async {
    final pdfPath = '${tmp.path}/bad.pdf';
    File(pdfPath).writeAsBytesSync(List.filled(1024, 0x42));
    final outPath = '${tmp.path}/bad.md';

    final controller = IsolateConversionController();
    await controller.convert(pdfPath: pdfPath, outputPath: outPath);

    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (controller.isRunning && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(controller.errorType, isNotNull);
    expect(File(outPath).existsSync(), isFalse);
    controller.dispose();
  });
}
