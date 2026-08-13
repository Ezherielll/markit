import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Builder .docx sintetis (zip + XML string) — dipakai test extractor.
///
/// [includeDocumentXml] false → entry `word/document.xml` dihilangkan
/// (mensimulasikan DOCX rusak tanpa entry utama).
Uint8List buildTestDocx({
  required String documentXml,
  String? stylesXml,
  String? numberingXml,
  bool includeDocumentXml = true,
}) {
  final archive = Archive();
  if (includeDocumentXml) {
    archive.addFile(ArchiveFile.string('word/document.xml', documentXml));
  }
  archive.addFile(ArchiveFile.string(
    '[Content_Types].xml',
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types/>',
  ));
  if (stylesXml != null) {
    archive.addFile(ArchiveFile.string('word/styles.xml', stylesXml));
  }
  if (numberingXml != null) {
    archive.addFile(ArchiveFile.string('word/numbering.xml', numberingXml));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Pembungkus `<w:document>` minimal dengan namespace WordprocessingML.
String docxDocument(String bodyInner) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:document xmlns:w="http://schemas.openxmlformats.org/'
    'wordprocessingml/2006/main"><w:body>$bodyInner<w:sectPr/></w:body>'
    '</w:document>';

/// Satu paragraf `<w:p>`: [runs] = konten run mentah, opsional styleId/numId.
String docxParagraph(
  String runs, {
  String? styleId,
  String? numId,
}) {
  final pPr = StringBuffer();
  if (styleId != null) {
    pPr.write('<w:pPr><w:pStyle w:val="$styleId"/></w:pPr>');
  } else if (numId != null) {
    pPr.write('<w:pPr><w:numPr><w:numId w:val="$numId"/></w:numPr></w:pPr>');
  }
  return '<w:p>$pPr$runs</w:p>';
}

/// Run teks sederhana `<w:r><w:t>`.
String docxRun(String text, {bool preserve = true}) =>
    '<w:r><w:t xml:space="${preserve ? 'preserve' : 'default'}">'
    '$text</w:t></w:r>';

/// Styles.xml minimal: peta styleId → nama heading.
String docxStyles(List<(String styleId, String name)> styles) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<w:styles xmlns:w="http://schemas.openxmlformats.org/'
    'wordprocessingml/2006/main">'
    '${styles.map((s) => '<w:style w:type="paragraph" w:styleId="${s.$1}">'
        '<w:name w:val="${s.$2}"/></w:style>').join()}</w:styles>';
