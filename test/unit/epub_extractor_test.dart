import 'package:flutter_test/flutter_test.dart';
import 'package:markit/core/errors.dart';
import 'package:markit/core/extractors/epub_extractor.dart';
import 'package:markit/core/extractors/xhtml_to_blocks.dart';
import 'package:markit/models/layout.dart';
import 'package:markit/core/output.dart';

import '../helpers/zip_factory.dart';

const _container = '<?xml version="1.0"?>'
    '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container" version="1.0">'
    '<rootfiles><rootfile full-path="OEBPS/content.opf" '
    'media-type="application/oebps-package+xml"/></rootfiles></container>';

const _opf = '<?xml version="1.0"?>'
    '<package xmlns="http://www.idpf.org/2007/opf" version="3.0">'
    '<manifest><item id="ch1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
    '<item id="ch2" href="ch2.xhtml" media-type="application/xhtml+xml"/></manifest>'
    '<spine><itemref idref="ch1"/><itemref idref="ch2"/></spine></package>';

Future<String> _run(Map<String, String> entries) async {
  final output = MemoryOutput();
  final result = await const EpubExtractor().extract(
    bytes: buildZip(entries),
    output: output,
  );
  expect(result.itemCount, greaterThan(0));
  return output.content;
}

void main() {
  test('spine chapters → headings, paragraphs, lists', () async {
    final md = await _run({
      'META-INF/container.xml': _container,
      'OEBPS/content.opf': _opf,
      'OEBPS/ch1.xhtml': '<html><body><h1>Chapter One</h1>'
          '<p>First <strong>bold</strong> paragraph.</p>'
          '<ul><li>One</li><li>Two</li></ul></body></html>',
      'OEBPS/ch2.xhtml': '<html><body><h2>Section Two</h2>'
          '<p>See <a href="https://example.com">docs</a>.</p></body></html>',
    });
    expect(md, contains('# Chapter One'));
    expect(md, contains('First **bold** paragraph.'));
    expect(md, contains('- One'));
    expect(md, contains('## Section Two'));
    expect(md, contains('docs (https://example.com)'));
  });

  test('tables and nested lists', () async {
    final md = await _run({
      'META-INF/container.xml': _container,
      'OEBPS/content.opf': _opf,
      'OEBPS/ch1.xhtml': '<html><body>'
          '<table><tr><th>A</th><th>B</th></tr><tr><td>1</td><td>2</td></tr></table>'
          '<ul><li>Outer<ul><li>Inner</li></ul></li></ul>'
          '</body></html>',
      'OEBPS/ch2.xhtml': '<html><body><p>Empty chapter.</p></body></html>',
    });
    expect(md, contains('| A | B |'));
    expect(md, contains('| 1 | 2 |'));
    expect(md, contains('- Outer'));
    expect(md, contains('  - Inner'));
  });

  test('missing container.xml → corrupt', () async {
    expect(
      () => const EpubExtractor().extract(
        bytes: buildZip({'random.txt': 'x'}),
        output: MemoryOutput(),
      ),
      throwsA(isA<ConvertException>()),
    );
  });

  test('xhtmlToBlocks: heading levels h1-h6', () {
    final blocks = xhtmlToBlocks('<html><body>'
        '<h1>One</h1><h2>Two</h2><h3>Three</h3>'
        '<h4>Four</h4><h5>Five</h5><h6>Six</h6>'
        '</body></html>');
    final headings = blocks.where((b) => b.type == BlockType.heading).toList();
    expect(headings, hasLength(6));
    for (var i = 0; i < 6; i++) {
      expect(headings[i].headingLevel, i + 1);
      expect(headings[i].text, ['One', 'Two', 'Three', 'Four', 'Five', 'Six'][i]);
    }
  });

  test('xhtmlToBlocks: nested lists get increasing listDepth', () {
    final blocks = xhtmlToBlocks('<html><body>'
        '<ul><li>Outer<ul><li>Inner<ul><li>Deep</li></ul></li></ul></li></ul>'
        '</body></html>');
    final items = blocks.where((b) => b.type == BlockType.unorderedListItem).toList();
    expect(items, hasLength(3));
    expect(items[0].text, 'Outer');
    expect(items[0].listDepth, 0);
    expect(items[1].text, 'Inner');
    expect(items[1].listDepth, 1);
    expect(items[2].text, 'Deep');
    expect(items[2].listDepth, 2);
  });

  test('xhtmlToBlocks: script and style content is skipped', () {
    final blocks = xhtmlToBlocks('<html><head><title>T</title>'
        '<script>var x = 1;</script><style>p { color: red; }</style></head>'
        '<body><p>Visible</p><script>alert("hidden");</script>'
        '<style>.hidden {}</style></body></html>');
    final text = blocks.map((b) => b.text).join('\n');
    expect(text, contains('Visible'));
    expect(text, isNot(contains('var x')));
    expect(text, isNot(contains('color: red')));
    expect(text, isNot(contains('alert')));
    expect(text, isNot(contains('hidden')));
  });
}
