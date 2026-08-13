import '../extractor.dart';
import '../input_format.dart';
import 'csv_extractor.dart';
import 'docx_extractor.dart';

/// Registry extractor per keluarga format.
///
/// PDF tidak masuk di sini — jalur PDF adalah pipeline existing
/// (PdfrxSource → grouper → classifier) yang dirouting di executor
/// (penyatuan ke seam yang sama ada di roadmap). Keluarga tanpa extractor
/// (powerpoint/excel/opendocument/rtf/epub) → null: terdeteksi & bisa
/// dipilih, lalu gagal dengan pesan "not supported yet" yang jelas.
class ExtractorRegistry {
  const ExtractorRegistry._();

  static final Map<InputFormat, FormatExtractor> _extractors = {
    InputFormat.word: const DocxExtractor(),
    InputFormat.csv: const CsvExtractor(),
  };

  /// Extractors non-PDF; null → format belum didukung konversi.
  static FormatExtractor? forFormat(InputFormat format) => _extractors[format];
}
