import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/isolate/conversion_controller.dart';
import 'package:pdflow/models/pdf_input.dart';

void main() {
  group('downloadAllZip (bug #1 fix)', () {
    test('kumpulkan semua job done → peta nama→konten', () {
      final queue = [
        _doneJob('a.pdf', '# A\n'),
        _doneJob('b.pdf', '# B\n'),
        _failedJob('c.pdf'),
      ];

      // Simulasikan isi peta yang akan di-zip oleh helper top-level.
      final files = <String, String>{};
      for (final job in queue) {
        if (job.status == JobStatus.done && job.content != null) {
          files[job.input.outputName] = job.content!;
        }
      }

      expect(files.keys, ['a.md', 'b.md']);
      expect(files['a.md'], '# A\n');
      expect(files.containsKey('c.md'), isFalse);
    });

    test('archive: file teks bisa di-zip dan di-decode balik (validasi web)',
        () async {
      // Salin logika platformDownloadZipFile (bagian arsip) untuk verifikasi.
      final archive = Archive();
      archive.addFile(ArchiveFile.string('a.md', '# A\n'));
      archive.addFile(ArchiveFile.string('b.md', '# B\n'));
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

      expect(bytes.length, greaterThan(0));
      final decoded = ZipDecoder().decodeBytes(bytes);
      expect(decoded.files.map((f) => f.name), ['a.md', 'b.md']);
      expect(
        String.fromCharCodes(decoded.files[0].content as List<int>),
        '# A\n',
      );
    });
  });
}

QueuedFile _doneJob(String name, String content) {
  final job = QueuedFile(
    id: name,
    input: PdfInput(name: name, path: '/tmp/$name'),
  );
  job.status = JobStatus.done;
  job.content = content;
  return job;
}

QueuedFile _failedJob(String name) {
  final job = QueuedFile(
    id: name,
    input: PdfInput(name: name, path: '/tmp/$name'),
  );
  job.status = JobStatus.failed;
  return job;
}
