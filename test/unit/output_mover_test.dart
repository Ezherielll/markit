import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/output_mover.dart';

void main() {
  late Directory tmp;
  late Directory src;
  late Directory dst;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('markit_move');
    src = Directory('${tmp.path}/src')..createSync();
    dst = Directory('${tmp.path}/dst')..createSync();
  });

  tearDown(() async {
    await tmp.delete(recursive: true);
  });

  group('planOutputMoves', () {
    test('susun pasangan from→to dan deteksi konflik', () {
      File('${src.path}/a.md').writeAsStringSync('a');
      File('${src.path}/b.md').writeAsStringSync('b');
      File('${dst.path}/b.md').writeAsStringSync('old');

      final plan = planOutputMoves([
        ('${src.path}/a.md', 'a.md'),
        ('${src.path}/b.md', 'b.md'),
      ], dst.path);

      expect(plan.moves, hasLength(2));
      expect(plan.moves[0].$2, '${dst.path}/a.md');
      expect(plan.conflicts, ['${dst.path}/b.md']);
      expect(plan.hasConflicts, isTrue);
    });

    test('tanpa konflik → hasConflicts false', () {
      final plan = planOutputMoves([('${src.path}/a.md', 'a.md')], dst.path);
      expect(plan.hasConflicts, isFalse);
      expect(plan.conflicts, isEmpty);
    });

    test('target duplikat dalam batch: move kedua dibuang & masuk konflik', () {
      final plan = planOutputMoves([
        ('${src.path}/a.md', 'a.md'),
        ('${src.path}/sub/a.md', 'a.md'),
      ], dst.path);

      expect(plan.moves, hasLength(1));
      expect(plan.moves.single, ('${src.path}/a.md', '${dst.path}/a.md'));
      expect(plan.conflicts, ['${dst.path}/a.md']);
      expect(plan.hasConflicts, isTrue);
    });
  });

  group('applyOutputMoves', () {
    test('overwrite=false: konflik di-skip, sisanya dipindah', () async {
      File('${src.path}/a.md').writeAsStringSync('a');
      File('${src.path}/b.md').writeAsStringSync('b');
      File('${dst.path}/b.md').writeAsStringSync('old');

      final plan = planOutputMoves([
        ('${src.path}/a.md', 'a.md'),
        ('${src.path}/b.md', 'b.md'),
      ], dst.path);

      final applied = await applyOutputMoves(plan, overwrite: false);

      expect(applied, hasLength(1));
      expect(applied.single.$2, '${dst.path}/a.md');
      expect(File('${src.path}/a.md').existsSync(), isFalse);
      expect(File('${dst.path}/a.md').existsSync(), isTrue);
      // b.md konflik: tetap di sumber, target lama utuh
      expect(File('${src.path}/b.md').existsSync(), isTrue);
      expect(File('${dst.path}/b.md').readAsStringSync(), 'old');
    });

    test('overwrite=true: target dihapus dulu lalu diganti', () async {
      File('${src.path}/b.md').writeAsStringSync('new');
      File('${dst.path}/b.md').writeAsStringSync('old');

      final plan = planOutputMoves([('${src.path}/b.md', 'b.md')], dst.path);
      final applied = await applyOutputMoves(plan, overwrite: true);

      expect(applied, hasLength(1));
      expect(File('${dst.path}/b.md').readAsStringSync(), 'new');
      expect(File('${src.path}/b.md').existsSync(), isFalse);
    });

    test('target duplikat batch + overwrite=true: hanya satu dipindah, tanpa kehilangan isi', () async {
      File('${src.path}/a.md').writeAsStringSync('konten A');
      final sub = Directory('${src.path}/sub')..createSync();
      File('${sub.path}/a.md').writeAsStringSync('konten B');
      File('${dst.path}/a.md').writeAsStringSync('old');

      final plan = planOutputMoves([
        ('${src.path}/a.md', 'a.md'),
        ('${src.path}/sub/a.md', 'a.md'),
      ], dst.path);
      final applied = await applyOutputMoves(plan, overwrite: true);

      expect(applied, hasLength(1));
      expect(File('${dst.path}/a.md').readAsStringSync(), 'konten A');
      // File kedua tetap di sumber — tidak ditimpa/saling menghapus.
      expect(File('${src.path}/sub/a.md').existsSync(), isTrue);
      expect(File('${src.path}/sub/a.md').readAsStringSync(), 'konten B');
    });

    test('from == to dengan overwrite=true: di-skip, tanpa exception', () async {
      final path = '${src.path}/x.md';
      File(path).writeAsStringSync('isi');
      final plan = OutputMovePlan(moves: [(path, path)], conflicts: []);
      final applied = await applyOutputMoves(plan, overwrite: true);

      expect(applied, isEmpty);
      expect(File(path).existsSync(), isTrue);
      expect(File(path).readAsStringSync(), 'isi');
    });

    test('from == to beda separator (path kanonik): di-skip, tanpa exception',
        skip: !Platform.isWindows, () async {
      // Di POSIX '\' bukan path separator — skenario ini hanya berlaku Windows.
      if (!Platform.isWindows) {
        markTestSkipped('separator campuran hanya relevan di Windows');
        return;
      }
      final from = '${dst.path}/a.md';
      final to = from.replaceAll('/', r'\');
      File(from).writeAsStringSync('isi');
      final plan = OutputMovePlan(moves: [(from, to)], conflicts: []);
      final applied = await applyOutputMoves(plan, overwrite: true);

      expect(applied, isEmpty);
      expect(File(from).existsSync(), isTrue);
      expect(File(from).readAsStringSync(), 'isi');
    });
  });
}
