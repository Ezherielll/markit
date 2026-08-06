import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/converter.dart';
import 'package:markit/core/output.dart';
import 'package:markit/core/pdfrx_source.dart';
import 'package:markit/isolate/conversion_executor.dart';
import 'package:markit/isolate/convert_isolate.dart';
import 'package:markit/isolate/messages.dart';

import '../helpers/pdf_factory.dart';

/// M1 spike: apakah PDFium aman untuk multi-dokumen CONCURRENT?
/// - inline (main isolate, seperti web): 3 job sekaligus.
/// - worker: 3 StartConvert dikirim sekaligus via protokol mentah
///   (bypass IsolateExecutor — handler tunggalnya bukan bagian dari spike;
///   routing per-jobId dikerjakan di M2).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<Uint8List> pdfBytes;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_conc');
    pdfBytes = [
      buildTestPdf(pages: largeBookPages(40, chapterEvery: 10)),
      buildTestPdf(pages: largeBookPages(25, chapterEvery: 5)),
      buildTestPdf(pages: largeBookPages(60, chapterEvery: 15)),
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

  test('spike: 3 job concurrent di main isolate (seperti web/inline)', () async {
    final rssBefore = ProcessInfo.currentRss;
    final results = await Future.wait([
      for (var i = 0; i < pdfBytes.length; i++) _convert(i, pdfBytes[i]),
    ]);
    final rssAfter = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('[spike-inline] deltaRSS=${(rssAfter - rssBefore) ~/ (1024 * 1024)} MB');

    for (var i = 0; i < results.length; i++) {
      expect(results[i].success, isTrue);
      expect(results[i].content, contains('# Chapter 1'));
    }
    // ignore: avoid_print
    print('[spike-inline] 3 concurrent OK');
  });

  test('spike: 3 StartConvert sekaligus ke satu worker (raw protocol)', () async {
    final rssBefore = ProcessInfo.currentRss;
    // Worker membaca dari path file.
    final paths = <String>[];
    for (var i = 0; i < pdfBytes.length; i++) {
      final p = '${tmp.path}/in$i.pdf';
      File(p).writeAsBytesSync(pdfBytes[i]);
      paths.add(p);
    }

    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(convertIsolateMain, receivePort.sendPort);

    final results = <String, bool>{};
    final done = <String, String>{};
    final completers = <String, Completer<void>>{};
    for (var i = 0; i < paths.length; i++) {
      completers['job$i'] = Completer<void>();
    }

    // Pesan 1: commandPort (kirim semua StartConvert). Pesan 2+: hasil job.
    var gotCommand = false;
    final sub = receivePort.listen((message) {
      if (message is SendPort && !gotCommand) {
        gotCommand = true;
        for (var i = 0; i < paths.length; i++) {
          message.send(StartConvert(
            jobId: 'job$i',
            pdfPath: paths[i],
            outputPath: '${tmp.path}/out$i.md',
          ));
        }
        return;
      }
      if (message is ConvertDone) {
        results[message.jobId] = true;
        done[message.jobId] = message.outputPath;
        completers[message.jobId]?.complete();
      } else if (message is ConvertFailed) {
        results[message.jobId] = false;
        completers[message.jobId]?.complete();
      }
    });

    await Future.wait(completers.values.map((c) => c.future))
        .timeout(const Duration(seconds: 60));
    await sub.cancel();
    final rssAfter = ProcessInfo.currentRss;
    // ignore: avoid_print
    print('[spike-worker] deltaRSS=${(rssAfter - rssBefore) ~/ (1024 * 1024)} MB');

    expect(results.length, 3, reason: 'harusnya 3 Done/Failed diterima');
    for (final id in results.keys) {
      expect(results[id], isTrue, reason: '$id gagal');
      expect(File(done[id]!).existsSync(), isTrue);
    }

    isolate.kill();
    receivePort.close();
    // ignore: avoid_print
    print('[spike-worker] 3 concurrent OK');
  });

  test('spike: 6 file sekaligus via raw protocol (batas atas realistic)',
      () async {
    final receivePort = ReceivePort();
    final isolate = await Isolate.spawn(convertIsolateMain, receivePort.sendPort);

    final files = [
      ...pdfBytes,
      buildTestPdf(pages: largeBookPages(15, chapterEvery: 5)),
      buildTestPdf(pages: largeBookPages(30, chapterEvery: 6)),
      buildTestPdf(pages: largeBookPages(20, chapterEvery: 4)),
    ];
    final paths = <String>[];
    for (var i = 0; i < files.length; i++) {
      final p = '${tmp.path}/in6_$i.pdf';
      File(p).writeAsBytesSync(files[i]);
      paths.add(p);
    }

    final results = <String, bool>{};
    final completers = <String, Completer<void>>{};
    for (var i = 0; i < paths.length; i++) {
      completers['job$i'] = Completer<void>();
    }

    var gotCommand = false;
    final sub = receivePort.listen((message) {
      if (message is SendPort && !gotCommand) {
        gotCommand = true;
        for (var i = 0; i < paths.length; i++) {
          message.send(StartConvert(
            jobId: 'job$i',
            pdfPath: paths[i],
            outputPath: '${tmp.path}/out6_$i.md',
          ));
        }
        return;
      }
      if (message is ConvertDone || message is ConvertFailed) {
        results[message.jobId] = message is ConvertDone;
        completers[message.jobId]?.complete();
      }
    });

    await Future.wait(completers.values.map((c) => c.future))
        .timeout(const Duration(seconds: 60));
    await sub.cancel();
    expect(results.length, paths.length, reason: 'harusnya semua selesai');
    for (final id in results.keys) {
      expect(results[id], isTrue, reason: '$id gagal');
    }

    isolate.kill();
    receivePort.close();
    // ignore: avoid_print
    print('[spike-worker] 6 concurrent OK');
  });
}

Future<JobExecutionResult> _convert(int index, Uint8List bytes) async {
  final source = await PdfrxSource.openData(bytes, sourceName: 'spike$index');
  try {
    final output = MemoryOutput();
    await Converter().convert(source: source, output: output);
    return JobExecutionResult(
      success: true,
      pageCount: source.pageCount,
      failedPages: const [],
      bodyFontSize: 0,
      content: output.content,
    );
  } finally {
    await source.dispose();
  }
}
