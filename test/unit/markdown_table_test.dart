import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/markdown_table.dart';

void main() {
  group('tableToMarkdown', () {
    test('rows become header + separator + body', () {
      final md = tableToMarkdown([
        ['Name', 'Age'],
        ['Alice', '30'],
        ['Bob', '25'],
      ]);
      expect(md, '| Name | Age |\n| --- | --- |\n| Alice | 30 |\n| Bob | 25 |');
    });

    test('cell pipe and newline are escaped', () {
      final md = tableToMarkdown([
        ['a|b', 'x\ny'],
      ]);
      expect(md, contains(r'\|'));
      expect(md, isNot(contains('\n\n')));
    });

    test('empty rows produce empty string', () {
      expect(tableToMarkdown([]), '');
    });
  });
}
