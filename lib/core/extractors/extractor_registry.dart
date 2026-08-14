import '../extractor.dart';
import '../input_format.dart';
import 'csv_extractor.dart';
import 'docx_extractor.dart';
import 'pdf_extractor.dart';

/// Extractor registry per format family — the single dispatch point.
///
/// PDF is an adapter like any other ([PdfExtractor] over the existing
/// two-pass pipeline). Families without an extractor
/// (powerpoint/excel/opendocument/rtf/epub) → null: detected & selectable,
/// failing with a clear "not supported yet" error.
class ExtractorRegistry {
  const ExtractorRegistry._();

  static final Map<InputFormat, FormatExtractor> _extractors = {
    InputFormat.pdf: const PdfExtractor(),
    InputFormat.word: const DocxExtractor(),
    InputFormat.csv: const CsvExtractor(),
  };

  /// Extractors for all convertible formats; null → not supported yet.
  static FormatExtractor? forFormat(InputFormat format) => _extractors[format];
}
