import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:markit/ui/widgets/markdown_helpers.dart';

void main() {
  group('computeMdStats — akurat untuk konten non-PDF (M3)', () {
    test('fenced code block tidak dihitung sebagai paragraphs', () {
      final stats = computeMdStats(
        '# Title\n\nSome text.\n\n```json\n{"a": 1,\n"b": [2, 3]}\n```\n\n'
        'Trailing.\n',
      );
      expect(stats.headings, 1);
      expect(stats.paragraphs, 2);
      expect(stats.listItems, 0);
      expect(stats.tableRows, 0);
    });

    test('baris tabel dihitung sebagai rows, bukan paragraphs', () {
      final stats = computeMdStats(
        '| Name | Age |\n| --- | --- |\n| Alice | 30 |\n| Bob | 25 |\n',
      );
      expect(stats.tableRows, 4);
      expect(stats.paragraphs, 0);
    });

    test('fenced block multi-lapisan (tidak valid md) tetap skip', () {
      final stats = computeMdStats('```\nline1\n```\n# H\n```\nline2\n```\n');
      expect(stats.headings, 1);
      expect(stats.paragraphs, 0);
    });
  });

  group('render preview multi-format tanpa overflow (M1/M2)', () {
    Widget wrap(String data, {Map<String, MarkdownElementBuilder>? builders}) {
      return Builder(
        builder: (context) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: MarkdownBody(
                  data: data,
                  styleSheet: documentMarkdownStyle(context),
                  builders: builders ?? const {},
                ),
              ),
            ),
          ),
        ),
      );
    }

    testWidgets('tabel CSV lebar (20 kolom) render tanpa exception',
        (tester) async {
      final cols = List.generate(20, (i) => 'Col$i').join(' | ');
      final rows = List.generate(50, (i) =>
          List.generate(20, (j) => 'v$i-$j').join(' | ')).join('\n');
      final data = '| $cols |\n| ${List.filled(20, '---').join(' | ')} |\n'
          '$rows\n';

      await tester.pumpWidget(wrap(data));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });

    testWidgets('code block default: baris panjang no-wrap + scroll horizontal',
        (tester) async {
      final long = 'x' * 400;
      final data = '```json\n{"long": "$long",\n"a": 1}\n```\n';

      await tester.pumpWidget(wrap(data));
      await tester.pump();

      expect(tester.takeException(), isNull);
      // Default flutter_markdown membungkus baris code block dalam
      // SingleChildScrollView horizontal (unbounded width → no-wrap).
      final hScrolls = tester
          .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
          .where((w) => w.scrollDirection == Axis.horizontal)
          .toList();
      expect(hScrolls, isNotEmpty,
          reason: 'code block harus punya horizontal scroll');
    });
  });
}
