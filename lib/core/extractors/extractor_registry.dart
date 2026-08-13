import '../extractor.dart';
import '../input_format.dart';
import 'csv_extractor.dart';
import 'docx_extractor.dart';

/// Extractor registry per format family.
///
/// PDF is not included here — PDF path uses existing pipeline
/// (PdfrxSource → grouper → classifier) routed in executor
/// (unification into same seam is on roadmap). Families without extractor
/// (powerpoint/excel/opendocument/rtf/epub) → null: detected & selectable,
/// failing with clear "not supported yet" error.
class ExtractorRegistry {
  const ExtractorRegistry._();

  static final Map<InputFormat, FormatExtractor> _extractors = {
    InputFormat.word: const DocxExtractor(),
    InputFormat.csv: const CsvExtractor(),
  };

  /// Non-PDF extractors; null → format conversion not supported yet.
  static FormatExtractor? forFormat(InputFormat format) => _extractors[format];
}
