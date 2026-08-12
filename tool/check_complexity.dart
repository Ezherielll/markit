import 'dart:io';

import 'package:cognitive_complexity/cognitive_complexity.dart';

/// Gate Cognitive Complexity (Fase D): gagalkan bila ada fungsi di lib/
/// dengan score > threshold (default 15 — rekomendasi SonarSource).
///
/// Usage: dart run tool/check_complexity.dart [threshold]
void main(List<String> args) {
  final threshold = args.isEmpty ? 15 : int.parse(args.first);
  final analyzer = ComplexityAnalyzer();
  final results = analyzer.analyzePath('lib');

  final offenders = results.where((r) => r.score > threshold).toList()
    ..sort((a, b) => b.score.compareTo(a.score));

  if (offenders.isEmpty) {
    stdout.writeln('OK: semua fungsi <= $threshold (cognitive complexity)');
    return;
  }

  stdout.writeln('FAIL: ${offenders.length} fungsi > $threshold:');
  for (final r in offenders) {
    stdout.writeln('  ${r.score}  ${r.name}  (${r.filePath}:L${r.startLine})');
  }
  exitCode = 1;
}
