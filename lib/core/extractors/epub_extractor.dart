import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../../models/layout.dart';
import '../errors.dart';
import '../extractor.dart';
import '../input_format.dart';
import '../markdown_writer.dart';
import '../output.dart';
import 'input_bytes.dart';
import 'xhtml_to_blocks.dart';

/// EPUB extractor → markdown: resolves container.xml → content.opf → spine
/// (manifest hrefs relative to the OPF directory) and converts each XHTML
/// chapter via [xhtmlToBlocks]. Chapters are separated by a blank line.
class EpubExtractor implements FormatExtractor {
  const EpubExtractor();

  @override
  InputFormat get format => InputFormat.epub;

  @override
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required OutputTarget output,
    void Function(int done, int total, int phase, int elapsedMs)? onProgress,
    bool Function()? isCancelled,
  }) {
    return withMarkdownWriter(output, run: (writer) async {
      final raw = await readInputBytes(bytes, path);
      if (raw == null) {
        throw ConvertException(
          ConvertError.corrupt,
          'Could not read the EPUB file.',
        );
      }
      final archive = _openZip(raw);
      final blocks = _collectBlocks(archive);
      return _emit(blocks, writer, onProgress, isCancelled);
    });
  }

  /// container.xml → content.opf → spine chapters → blocks, with a blank
  /// line between chapters. Missing chapters are tolerated; a missing or
  /// empty spine structure, or no extractable text at all, → ConvertException.
  List<Block> _collectBlocks(Archive archive) {
    // container.xml → rootfile full-path.
    final containerXml = _entryText(archive, 'META-INF/container.xml');
    if (containerXml == null) {
      throw ConvertException(
        ConvertError.corrupt,
        'The EPUB file has no META-INF/container.xml.',
      );
    }
    final opfPath = _rootfilePath(containerXml);
    if (opfPath == null) {
      throw ConvertException(
        ConvertError.corrupt,
        'The EPUB container.xml has no rootfile.',
      );
    }

    // content.opf → ordered spine hrefs (resolved against the OPF dir).
    final opfXml = _entryText(archive, opfPath);
    if (opfXml == null) {
      throw ConvertException(
        ConvertError.corrupt,
        'The EPUB file has no $opfPath.',
      );
    }
    final opfDir = opfPath.contains('/')
        ? opfPath.substring(0, opfPath.lastIndexOf('/') + 1)
        : '';
    final chapters = _spineHrefs(opfXml).map((h) => opfDir + h).toList();
    if (chapters.isEmpty) {
      throw ConvertException(
        ConvertError.corrupt,
        'The EPUB spine is empty.',
      );
    }

    final blocks = <Block>[];
    for (final chapter in chapters) {
      final xhtml = _entryText(archive, chapter);
      if (xhtml == null) continue; // missing chapter tolerated
      if (blocks.isNotEmpty) {
        blocks.add(Block(type: BlockType.paragraph, lines: ['']));
      }
      blocks.addAll(xhtmlToBlocks(xhtml));
    }
    if (blocks.every((b) => b.text.trim().isEmpty)) {
      throw ConvertException(
        ConvertError.noText,
        'No text could be extracted from the EPUB file.',
      );
    }
    return blocks;
  }

  /// Write blocks to the writer; cancel mid-way via [isCancelled].
  ExtractionResult _emit(
    List<Block> blocks,
    MarkdownWriter writer,
    void Function(int done, int total, int phase, int elapsedMs)? onProgress,
    bool Function()? isCancelled,
  ) {
    var done = 0;
    for (final b in blocks) {
      if (isCancelled?.call() ?? false) break;
      writer.writeBlock(b);
      done++;
      onProgress?.call(done, blocks.length, 1, 0);
    }
    return ExtractionResult(itemCount: done);
  }

  /// `container.xml` → `rootfile@full-path` (any namespace); null when the
  /// file has no rootfile element or attribute.
  String? _rootfilePath(String containerXml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(containerXml);
    } on XmlException catch (e) {
      throw ConvertException(
        ConvertError.corrupt,
        'The EPUB container.xml is not valid XML: ${e.message}',
      );
    }
    final rootfile = doc.descendants
        .whereType<XmlElement>()
        .where((e) => e.name.local == 'rootfile')
        .firstOrNull;
    return rootfile?.getAttribute('full-path', namespace: '*');
  }

  /// `content.opf` → spine hrefs in document order: manifest item id → href,
  /// then spine itemref@idref → href (unresolvable idrefs skipped).
  List<String> _spineHrefs(String opfXml) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(opfXml);
    } on XmlException catch (e) {
      throw ConvertException(
        ConvertError.corrupt,
        'The EPUB content.opf is not valid XML: ${e.message}',
      );
    }
    final hrefById = <String, String>{};
    for (final item in doc.descendants.whereType<XmlElement>()) {
      if (item.name.local != 'item') continue;
      final id = item.getAttribute('id', namespace: '*');
      final href = item.getAttribute('href', namespace: '*');
      if (id != null && href != null) hrefById[id] = href;
    }
    final hrefs = <String>[];
    for (final itemref in doc.descendants.whereType<XmlElement>()) {
      if (itemref.name.local != 'itemref') continue;
      final idref = itemref.getAttribute('idref', namespace: '*');
      final href = idref == null ? null : hrefById[idref];
      if (href != null) hrefs.add(href);
    }
    return hrefs;
  }

  String? _entryText(Archive archive, String name) {
    final entry =
        archive.files.where((f) => f.isFile && f.name == name).firstOrNull;
    if (entry == null) return null;
    return utf8.decode(entry.content as List<int>, allowMalformed: true);
  }

  Archive _openZip(Uint8List raw) {
    try {
      return ZipDecoder().decodeBytes(raw);
    } on ArchiveException {
      throw ConvertException(
        ConvertError.corrupt,
        'The EPUB file is not a valid ZIP archive.',
      );
    }
  }
}
