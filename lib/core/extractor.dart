import 'dart:typed_data';

import 'input_format.dart';
import 'markdown_writer.dart';

/// Hasil ekstraksi satu dokumen non-PDF.
class ExtractionResult {
  ExtractionResult({required this.itemCount, this.warnings = const []});

  /// Jumlah item (paragraf/baris/slide) — dipakai sebagai pageCount UI.
  final int itemCount;
  final List<String> warnings;
}

/// Abstraksi ekstraktor per format (pure Dart, tanpa FFI — jalan offline
/// di desktop & web).
///
/// Kontrak (plan §5.2):
/// - Error fatal (file korup) → lempar [ConvertException] (batch tetap lanjut).
/// - Partial content → tulis apa adanya + tambahkan [ExtractionResult.warnings].
/// - Cancel → [isCancelled] dicek per item; hentikan segera.
/// - Progress → [onProgress](done, total) per item (paragraf/baris/slide).
abstract class FormatExtractor {
  InputFormat get format;

  /// Ekstrak isi dokumen → blok markdown via [writer] (streaming).
  ///
  /// [bytes] selalu tersedia di web; di desktop worker, semantic extractor
  /// membaca [path] bila [bytes] null (jalur PDF tetap stream via path).
  Future<ExtractionResult> extract({
    required Uint8List? bytes,
    String? path,
    required MarkdownWriter writer,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  });
}
