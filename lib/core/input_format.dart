/// Input format families supported by MarkIt.
///
/// Enum value = format FAMILY ("Supported formats" list in UI: Word,
/// PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV, PDF). Extension details
/// (detection, legacy, preview) reside in `format_catalog.dart`.
enum InputFormat {
  word,
  powerpoint,
  excel,
  opendocument,
  rtf,
  epub,
  csv,
  pdf,
  unknown;

  String get label => switch (this) {
        word => 'Word',
        powerpoint => 'PowerPoint',
        excel => 'Excel',
        opendocument => 'OpenDocument',
        rtf => 'RTF',
        epub => 'EPUB',
        csv => 'CSV',
        pdf => 'PDF',
        unknown => 'Unknown',
      };
}
