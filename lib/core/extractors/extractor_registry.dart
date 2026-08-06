import '../extractor.dart';
import '../input_format.dart';
import 'csv_extractor.dart';
import 'html_extractor.dart';
import 'json_extractor.dart';
import 'text_extractor.dart';
import 'xml_extractor.dart';

/// Registry extractor per format.
///
/// PDF tidak masuk di sini — pipeline PDF adalah jalur existing
/// (PdfrxSource → grouper → classifier). Non-PDF yang didukung punya
/// semantic extractor pure-Dart.
class ExtractorRegistry {
  const ExtractorRegistry._();

  static final Map<InputFormat, FormatExtractor> _extractors = {
    InputFormat.text: const TextExtractor(),
    InputFormat.markdown: const TextExtractor(),
    InputFormat.csv: const CsvExtractor(),
    InputFormat.json: const JsonExtractor(),
    InputFormat.xml: const XmlExtractor(),
    InputFormat.html: const HtmlExtractor(),
  };

  /// Extractors non-PDF; null → format belum didukung (Fase 2–3 roadmap).
  static FormatExtractor? forFormat(InputFormat format) => _extractors[format];
}
