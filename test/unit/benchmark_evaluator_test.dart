import 'package:flutter_test/flutter_test.dart';
import '../../benchmark/golden_evaluator.dart';

void main() {
  group('Fase A metrics', () {
    test('headingLevelF1: hierarki sempurna → 1.0', () {
      const output = '# A\n\n## B\n\n### C\n\nBody text here.\n';
      const golden = '# A\n\n## B\n\n### C\n\nBody text here.\n';
      final report = evaluate(output, golden);
      expect(report.headingLevelF1, closeTo(1.0, 0.01));
    });

    test('headingLevelF1: level salah semua → 0.0', () {
      const output = '## A\n\n### B\n\n# C\n';
      const golden = '# A\n\n## B\n\n### C\n';
      final report = evaluate(output, golden);
      expect(report.headingLevelF1, closeTo(0.0, 0.01));
    });

    test('headingLevelF1: satu dari tiga benar → 1/3', () {
      const output = '# A\n\n# B\n\n# C\n';
      const golden = '# A\n\n## B\n\n### C\n';
      final report = evaluate(output, golden);
      // 1 dari 3 matched → precision 1/3, recall 1/3 → F1 = 1/3
      expect(report.headingLevelF1, closeTo(1 / 3, 0.01));
    });

    test('orderedListPrecision: urutan sempurna → 1.0', () {
      const output = '1. First\n\n2. Second\n\n3. Third\n';
      const golden = '1. First\n\n2. Second\n\n3. Third\n';
      final report = evaluate(output, golden);
      expect(report.orderedListPrecision, closeTo(1.0, 0.01));
    });

    test('orderedListPrecision: index salah → dihitung salah', () {
      const output = '1. First\n\n2. Third\n\n3. Second\n';
      const golden = '1. First\n\n2. Second\n\n3. Third\n';
      final report = evaluate(output, golden);
      // hanya (First,1) yang cocok → 1/3
      expect(report.orderedListPrecision, closeTo(1 / 3, 0.01));
    });

    test('orderedListPrecision: tidak ada ordered di output → 0.0', () {
      const output = '- First\n- Second\n';
      const golden = '1. First\n2. Second\n';
      final report = evaluate(output, golden);
      expect(report.orderedListPrecision, closeTo(0.0, 0.01));
    });

    test('wordCompleteness: kata hilang → recall < 1.0', () {
      const output = 'The quick fox jumps.';
      const golden = 'The quick brown fox jumps.';
      final report = evaluate(output, golden);
      // 4 dari 5 kata → 0.8
      expect(report.wordCompleteness, closeTo(0.8, 0.01));
    });

    test('wordCompleteness: identik → 1.0', () {
      const output = 'Hello world.';
      const golden = 'Hello world.';
      final report = evaluate(output, golden);
      expect(report.wordCompleteness, closeTo(1.0, 0.01));
    });

    test('metrik lama tetap berfungsi (paragraphF1, listRecall)', () {
      const output = '# Title\n\nSome paragraph.\n\n- item\n';
      const golden = '# Title\n\nSome paragraph.\n\n- item\n';
      final report = evaluate(output, golden);
      expect(report.paragraphF1, closeTo(1.0, 0.01));
      expect(report.listRecall, closeTo(1.0, 0.01));
      expect(report.headingAccuracy, closeTo(1.0, 0.01));
      expect(report.noiseBlocks, isEmpty);
    });
  });
}
