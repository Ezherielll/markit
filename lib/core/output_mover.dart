import 'dart:io';

/// Rencana pemindahan output .md ke folder pilihan user (fase "pilih lokasi").
class OutputMovePlan {
  const OutputMovePlan({required this.moves, required this.conflicts});

  /// Pasangan (path asal, path tujuan) untuk setiap file.
  final List<(String, String)> moves;

  /// Path tujuan yang SUDAH ADA di disk — butuh keputusan overwrite.
  final List<String> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Susun pemindahan: tiap (fromPath, fileName) → `directory/fileName`.
/// Target yang sudah ada di disk dicatat sebagai konflik (tidak dihapus).
/// Target duplikat dalam batch yang sama (dua input beda folder, nama sama)
/// DIBUANG dari [moves] dan targetnya masuk [conflicts] — file tetap di
/// sumber, tidak boleh saling timpa.
OutputMovePlan planOutputMoves(
  List<(String fromPath, String fileName)> outputs,
  String directory,
) {
  final moves = <(String, String)>[];
  final conflicts = <String>[];
  final seen = <String>{};
  for (final (from, name) in outputs) {
    final to = '$directory/$name';
    if (seen.contains(to)) {
      conflicts.add(to);
      continue;
    }
    seen.add(to);
    moves.add((from, to));
    if (File(to).existsSync()) conflicts.add(to);
  }
  return OutputMovePlan(moves: moves, conflicts: conflicts);
}

/// Terapkan rencana. Konflik: di-skip bila [overwrite] false (file tetap di
/// folder sumber); bila true, target dihapus dulu — File.rename di Windows
/// menolak tujuan yang sudah ada. Return pasangan (from, to) yang berhasil.
Future<List<(String, String)>> applyOutputMoves(
  OutputMovePlan plan, {
  required bool overwrite,
}) async {
  final applied = <(String, String)>[];
  for (final (from, to) in plan.moves) {
    // Bandingkan path kanonik: `.absolute.uri.toFilePath()` menormalisasi
    // separator (C:/a.md == C:\a.md di Windows) + membuang redundansi.
    if (File(from).absolute.uri.toFilePath() ==
        File(to).absolute.uri.toFilePath()) {
      continue;
    }
    final exists = await File(to).exists();
    if (exists && !overwrite) continue;
    if (exists) await File(to).delete();
    await File(from).rename(to);
    applied.add((from, to));
  }
  return applied;
}
