import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/models/pdf_input.dart';

void main() {
  group('QueuedFile.outputPath (fase pilih lokasi)', () {
    test('desktop: path sumber → ekstensi .md', () {
      final job = QueuedFile(
        id: '1',
        input: PdfInput(name: 'a.pdf', path: 'C:/docs/a.pdf'),
      );
      expect(job.outputPath, 'C:/docs/a.md');
    });

    test('web (tanpa path): nama → .md', () {
      final job = QueuedFile(
        id: '1',
        input: PdfInput(
          name: 'a.pdf',
          sizeBytes: 1,
          bytes: Uint8List(0),
        ),
      );
      expect(job.outputPath, 'a.md');
    });

    test('setter outputPath (setelah file dipindah ke folder pilihan)', () {
      final job = QueuedFile(
        id: '1',
        input: PdfInput(name: 'a.pdf', path: 'C:/docs/a.pdf'),
      );
      job.outputPath = 'D:/out/a.md';
      expect(job.outputPath, 'D:/out/a.md');
    });
  });
}
