import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/extractors/pdf_extractor.dart';
import 'package:markit/core/output.dart';

import '../helpers/pdf_factory.dart';

void main() {
  test('pdf bytes → markdown via MemoryOutput; phase 0 then 1', () async {
    final output = MemoryOutput();
    final phases = <int>[];
    final result = await const PdfExtractor().extract(
      bytes: buildTestPdf(),
      output: output,
      onProgress: (done, total, phase, elapsedMs) => phases.add(phase),
    );

    expect(result.itemCount, 3);
    expect(result.failedPages, isEmpty);
    expect(result.bodyFontSize, greaterThan(0));
    expect(result.outputPath, isNull);
    expect(output.content, contains('# The Quick Brown Fox'));
    // Phase 0 = reading marker (pass 1), then converting (pass 2).
    expect(phases.first, 0);
    expect(phases.sublist(1), everyElement(1));
  });

  test('random bytes → error thrown (executor maps to corrupt)', () async {
    expect(
      () => const PdfExtractor().extract(
        bytes: Uint8List.fromList([1, 2, 3]),
        output: MemoryOutput(),
      ),
      throwsA(anything),
    );
  });

  test('cancel from the start → error thrown (executor maps to failed)',
      () async {
    expect(
      () => const PdfExtractor().extract(
        bytes: buildTestPdf(),
        output: MemoryOutput(),
        isCancelled: () => true,
      ),
      throwsA(anything),
    );
  });
}
