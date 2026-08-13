import 'dart:io';

/// Plan for moving output .md files to user-selected folder.
class OutputMovePlan {
  const OutputMovePlan({required this.moves, required this.conflicts});

  /// Pair (source path, destination path) for each file.
  final List<(String, String)> moves;

  /// Destination paths that ALREADY EXIST on disk — require overwrite decision.
  final List<String> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Prepare move plan: each (fromPath, fileName) → `directory/fileName`.
/// Existing targets on disk recorded as conflicts (not deleted).
/// Duplicate targets within the same batch (two inputs from different folders, same name)
/// REMOVED from [moves] and target enters [conflicts] — files remain at
/// source, avoiding accidental overwrites.
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

/// Apply move plan. Conflicts: skipped if [overwrite] false (file remains at
/// source folder); if true, target is deleted first — File.rename on Windows
/// rejects existing destination. Returns list of successfully moved (from, to) pairs.
Future<List<(String, String)>> applyOutputMoves(
  OutputMovePlan plan, {
  required bool overwrite,
}) async {
  final applied = <(String, String)>[];
  for (final (from, to) in plan.moves) {
    // Compare canonical paths: normalize separators + remove redundancies.
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
