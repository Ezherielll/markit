import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pdflow/core/output.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('pdflow_output_test');
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('FileOutput (desktop)', () {
    test('commit: partial direname ke output, target lama ditimpa', () async {
      final outPath = '${tmp.path}/out.md';
      File(outPath).writeAsStringSync('old content');

      final output = FileOutput(outPath);
      final sink = await output.openSink();
      sink.write('new content');
      await sink.close();

      expect(File('$outPath.partial').existsSync(), isTrue);

      await output.commit();
      expect(File(outPath).readAsStringSync(), 'new content');
      expect(File('$outPath.partial').existsSync(), isFalse);
    });

    test('abort: partial dihapus, output tidak disentuh', () async {
      final outPath = '${tmp.path}/out.md';
      File(outPath).writeAsStringSync('keep me');

      final output = FileOutput(outPath);
      final sink = await output.openSink();
      sink.write('partial data');
      await sink.close();

      await output.abort();
      expect(File('$outPath.partial').existsSync(), isFalse);
      expect(File(outPath).readAsStringSync(), 'keep me');
    });
  });

  group('MemoryOutput (web)', () {
    test('commit: content tersedia, tidak ada file', () async {
      final output = MemoryOutput();
      final sink = await output.openSink();
      sink.write('# H1\n\nbody\n');
      await sink.close();

      await output.commit();
      expect(output.content, '# H1\n\nbody\n');
      expect(File('$tmp/whatever.md').existsSync(), isFalse);
    });

    test('abort: content tetap bisa dibaca (no-op)', () async {
      final output = MemoryOutput();
      final sink = await output.openSink();
      sink.write('data');
      await sink.close();

      await output.abort();
      expect(output.content, 'data');
    });
  });
}
