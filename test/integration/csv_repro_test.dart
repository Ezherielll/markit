// Integration test: CSV via jalur nyata desktop (IsolateExecutor) —\n// regression guard: format dideteksi dari header, dikonversi oleh semantic\n// extractor di worker, output .md valid.
@Tags(['desktop'])
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';

List<PdfInput> _inputsWithDetection(List<String> paths) => [
      for (final p in paths)
        PdfInput(
          name: p.split(RegExp(r'[\\/]')).last,
          path: p,
          format: detectFormat(
            p.split(RegExp(r'[\\/]')).last,
            _header(p),
          ),
        ),
    ];

Uint8List _header(String path) {
  try {
    final raf = File(path).openSync();
    try {
      return raf.readSync(65536);
    } finally {
      raf.closeSync();
    }
  } catch (_) {
    return Uint8List(0);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late BatchConversionController controller;

  setUpAll(() {
    controller = BatchConversionController();
  });

  tearDownAll(() async {
    await controller.shutdown();
  });

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_csv_repro');
  });
  tearDown(() async {
    controller.reset();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('csv via detectFormat + controller → done (multi-format bugfix)', () async {
    final csv = '${tmp.path}/data.csv';
    File(csv).writeAsStringSync('Name,Age\nAlice,30\nBob,25');

    final inputs = _inputsWithDetection([csv]);
    expect(inputs.single.format, InputFormat.csv,
        reason: 'format harusnya terdeteksi csv');

    controller.addFiles(inputs);
    await controller.convertAll();

    final job = controller.queue.single;
    expect(job.status, JobStatus.done,
        reason: 'status=${job.status} error=${job.errorType} ${job.errorMessage}');
    expect(File(job.outputPath).existsSync(), isTrue);
    expect(
      File(job.outputPath).readAsStringSync(),
      contains('| Name | Age |'),
    );
  });
}

