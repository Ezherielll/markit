import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/line_grouper.dart';
import 'package:markit/models/layout.dart';

TextSpan _span(String text, {double x = 0, double y = 100, double h = 12}) =>
    TextSpan(
      text: text,
      xLeft: x,
      xRight: x + text.length * 6,
      yBottom: y - h,
      yTop: y,
      fontSize: h,
    );

void main() {
  final grouper = LineGrouper();

  group('LineGrouper (FR-03)', () {
    test('span sebaris → satu baris, urut left-to-right', () {
      final lines = grouper.group([
        _span('fox', x: 40),
        _span('The ', x: 0),
        _span('brown ', x: 20),
      ]);
      expect(lines, hasLength(1));
      expect(lines.first.text, 'The brown fox');
    });

    test('dua baris terpisah vertikal → dua baris, top-to-bottom', () {
      final lines = grouper.group([
        _span('line A', y: 120),
        _span('line B', y: 100),
      ]);
      expect(lines, hasLength(2));
      expect(lines[0].text, 'line A');
      expect(lines[1].text, 'line B');
    });

    test('span dengan y sedikit bergeser tetap sebaris', () {
      final lines = grouper.group([
        _span('abc', y: 120),
        _span('def', y: 119.5),
        _span('ghi', y: 119),
      ]);
      expect(lines, hasLength(1));
      expect(lines.first.text, 'abcdefghi');
    });

    test('gabungan: 2 baris dengan multi-span tiap baris', () {
      final lines = grouper.group([
        _span('a', x: 0, y: 140, h: 18), // heading-ish
        _span('b', x: 10, y: 140, h: 18),
        _span('c', x: 0, y: 100), // body line 1
        _span('d', x: 12, y: 100),
        _span('e', x: 0, y: 80), // body line 2
      ]);
      expect(lines, hasLength(3));
      expect(lines[0].text, 'ab');
      expect(lines[1].text, 'cd');
      expect(lines[2].text, 'e');
    });
  });
}
