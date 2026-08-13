/// Keluarga format input yang didukung MarkIt.
///
/// Nilai enum = KELUARGA format (daftar "Supported formats" di UI: Word,
/// PowerPoint, Excel, OpenDocument, RTF, EPUB, CSV, PDF). Detail per
/// ekstensi (deteksi, legacy, preview) ada di `format_catalog.dart`.
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
