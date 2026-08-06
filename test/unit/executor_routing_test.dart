import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/isolate/inline_executor.dart';
import 'package:markit/isolate/isolate_executor.dart';

import '../helpers/pdf_factory.dart';

/// M2: routing per-jobId — 2+ job concurrent menghasilkan hasil yang BENAR
/// per job (tidak silang), untuk IsolateExecutor (desktop) & InlineExecutor (web).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<Uint8List> pdfBytes;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_route');
    pdfBytes = [
      buildTestPdf(pages: largeBookPages(30, chapterEvery: 10)),
      buildTestPdf(pages: largeBookPages(20, chapterEvery: 5)),
      buildTestPdf(pages: largeBookPages(45, chapterEvery: 9)),
    ];
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

  /// IsolateExecutor membaca dari path file (desktop) — tulis bytes ke disk.
  List<String> writeInputs() {
    final paths = <String>[];
    for (var i = 0; i < pdfBytes.length; i++) {
      final p = '${tmp.path}/in$i.pdf';
      File(p).writeAsBytesSync(pdfBytes[i]);
      paths.add(p);
    }
    return paths;
  }

  test('routing: 3 job concurrent di IsolateExecutor → hasil benar per job',
      () async {
    final executor = IsolateExecutor();
    await executor.initialize();
    final paths = writeInputs();

    final progressPerJob = <String, List<int>>{
      for (var i = 0; i < paths.length; i++) 'job$i': [],
    };

    final results = await Future.wait([
      for (var i = 0; i < paths.length; i++)
        executor.runJob(
          jobId: 'job$i',
          pdfPath: paths[i],
          outputPath: '${tmp.path}/out$i.md',
          onProgress: (page, total, phase, elapsedMs) {
            progressPerJob['job$i']!.add(page);
          },
        ),
    ]);

    // Setiap job berhasil dengan file outputnya sendiri (tidak silang).
    for (var i = 0; i < results.length; i++) {
      expect(results[i].success, isTrue, reason: 'job$i gagal');
      final md = File(results[i].outputPath!).readAsStringSync();
      expect(md, contains('# Chapter 1'), reason: 'job$i konten salah');
    }
    // Progress ter-routing: tiap job menerima progress page 0..N (tidak 0).
    for (var i = 0; i < paths.length; i++) {
      expect(progressPerJob['job$i']!, isNotEmpty, reason: 'job$i tanpa progress');
      expect(progressPerJob['job$i']!.length, greaterThan(3),
          reason: 'job$i progress terlalu sedikit');
    }

    await executor.shutdown();
  });

  test('routing: 3 job concurrent di InlineExecutor → hasil benar per job',
      () async {
    final executor = InlineExecutor();
    await executor.initialize();

    final results = await Future.wait([
      for (var i = 0; i < pdfBytes.length; i++)
        executor.runJob(
          jobId: 'job$i',
          pdfPath: '',
          pdfBytes: pdfBytes[i],
          outputPath: 'out$i.md',
        ),
    ]);

    for (var i = 0; i < results.length; i++) {
      expect(results[i].success, isTrue, reason: 'job$i gagal');
      expect(results[i].content, contains('# Chapter 1'));
    }
    await executor.shutdown();
  });

  test('routing: 1 gagal (corrupt) + 2 sukses → tidak silang (FR-10c)', () async {
    final executor = IsolateExecutor();
    await executor.initialize();

    final files = [
      Uint8List.fromList(List.filled(1024, 0x42)), // corrupt
      pdfBytes[0],
      pdfBytes[1],
    ];
    final paths = <String>[];
    for (var i = 0; i < files.length; i++) {
      final p = '${tmp.path}/mix$i.pdf';
      File(p).writeAsBytesSync(files[i]);
      paths.add(p);
    }
    final results = await Future.wait([
      for (var i = 0; i < paths.length; i++)
        executor.runJob(
          jobId: 'job$i',
          pdfPath: paths[i],
          outputPath: '${tmp.path}/mix_out$i.md',
        ),
    ]);

    expect(results[0].success, isFalse, reason: 'corrupt harus gagal');
    expect(results[1].success, isTrue);
    expect(results[2].success, isTrue);
    expect(File(results[1].outputPath!).readAsStringSync(), contains('# Chapter 1'));
    expect(File(results[2].outputPath!).readAsStringSync(), contains('# Chapter 1'));
    await executor.shutdown();
  });
}
