import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/isolate/conversion_controller.dart';

import '../helpers/pdf_factory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late BatchConversionController controller;

  // Satu controller untuk SEMUA test — worker persist tunggal, seperti app
  // nyata. pdfrx (PDFium) tidak aman di-spawn/teardown berulang dalam satu
  // proses ("Cannot invoke native callback from a different isolate").
  setUpAll(() {
    controller = BatchConversionController();
  });

  tearDownAll(() async {
    await controller.shutdown();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdflow_iso_test');
  });
  tearDown(() async {
    controller.reset();
    for (var i = 0; i < 5; i++) {
      try {
        await tmp.delete(recursive: true);
        break;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  Future<void> waitUntil(Future<bool> Function() cond) async {
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      if (await cond()) return;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    fail('timeout waiting for condition');
  }

  test('batch: 3 file valid → semua done, output ada (FR-08)', () async {
    final pdfs = [
      '${tmp.path}/a.pdf',
      '${tmp.path}/b.pdf',
      '${tmp.path}/c.pdf',
    ];
    for (final p in pdfs) {
      File(p).writeAsBytesSync(buildTestPdf());
    }

    controller.addFiles(pdfs);
    await controller.convertAll();

    expect(controller.doneCount, 3);
    for (final job in controller.queue) {
      expect(job.status, JobStatus.done);
      expect(File(job.outputPath).existsSync(), isTrue);
    }
  });

  test('batch: 1 corrupt + 2 valid → 1 failed, 2 done, batch lanjut (FR-10c)',
      () async {
    final pdfs = [
      '${tmp.path}/bad.pdf',
      '${tmp.path}/good1.pdf',
      '${tmp.path}/good2.pdf',
    ];
    File(pdfs[0]).writeAsBytesSync(List.filled(1024, 0x42));
    File(pdfs[1]).writeAsBytesSync(buildTestPdf());
    File(pdfs[2]).writeAsBytesSync(buildTestPdf());

    controller.addFiles(pdfs);
    await controller.convertAll();

    final bad = controller.queue.firstWhere((f) => f.pdfPath.endsWith('bad.pdf'));
    expect(bad.status, JobStatus.failed);
    expect(controller.doneCount, 2);
  });

  test('batch: cancel di tengah → sisa cancelled, .partial hilang (FR-11)',
      () async {
    // PDF besar sintetis agar ada waktu untuk cancel.
    final pdfs = [
      '${tmp.path}/big.pdf',
      '${tmp.path}/second.pdf',
    ];
    File(pdfs[0]).writeAsBytesSync(
      buildTestPdf(pages: largeBookPages(300)),
    );
    File(pdfs[1]).writeAsBytesSync(buildTestPdf());

    controller.addFiles(pdfs);

    final batchFuture = controller.convertAll();
    // Tunggu batch mulai, lalu cancel.
    await waitUntil(() async => controller.isRunning);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    controller.cancel();
    await batchFuture;

    // Job aktif dibatalkan (bukan done), sisanya cancelled.
    for (final job in controller.queue) {
      expect(job.status, isNot(JobStatus.queued));
      expect(job.status, isNot(JobStatus.done));
      expect(File('${job.outputPath}.partial').existsSync(), isFalse);
    }
  });

  test('batch ulang setelah cancel → worker persist dipakai lagi (ResetCancel)',
      () async {
    final pdf = '${tmp.path}/again.pdf';
    File(pdf).writeAsBytesSync(buildTestPdf());

    controller.addFiles([pdf]);
    await controller.convertAll();

    expect(controller.doneCount, 1);
    expect(controller.queue.single.status, JobStatus.done);
    expect(File(controller.queue.single.outputPath).existsSync(), isTrue);
  });
}
