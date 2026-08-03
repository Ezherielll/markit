import '../models/layout.dart';
import 'errors.dart';

/// Data ringkas satu halaman untuk pass 1 (histogram font).
class LightPageData {
  LightPageData({
    required this.pageIndex,
    required this.charCount,
    required this.lineHeights,
  });

  final int pageIndex;
  final int charCount;

  /// Tinggi bbox maksimum tiap baris teks (proxy fontSize, skala SAMA
  /// dengan [PdfrxSource.loadFull] — line height, bukan x-height).
  /// Dasar histogram body font (FR-05).
  final List<double> lineHeights;

  bool get hasText => charCount > 0;
}

/// Abstraksi sumber PDF (pure Dart).
///
/// Implementasi nyata: [PdfrxSource] (pdfrx/PDFium).
/// Di-inject agar pipeline dapat diuji dengan fake source tanpa file PDF.
abstract class PdfSource {
  int get pageCount;

  /// Apakah PDF dilindungi password.
  bool get isEncrypted;

  /// Pass 1: baca teks mentah + tinggi char saja (tanpa layout detail).
  /// [pageIndex] 0-based.
  Future<LightPageData> loadLight(int pageIndex);

  /// Pass 2: baca fragment berposisi (kata + bbox + proxy fontSize).
  /// [pageIndex] 0-based.
  Future<List<TextSpan>> loadFull(int pageIndex);

  Future<void> dispose();
}

/// Helper umum untuk klasifikasi error (FR-10a/b).
ConvertException mapOpenError(Object error) {
  // pdfrx: PDF dilindungi password dilempar sebagai PdfPasswordException
  // (termasuk bytes acak yang diinterpretasi PDFium sebagai encrypted).
  final name = error.runtimeType.toString();
  if (name.contains('Password')) {
    return ConvertException(
      ConvertError.encrypted,
      'PDF dilindungi password — tidak didukung.',
      cause: error,
    );
  }
  return ConvertException(
    ConvertError.corrupt,
    'PDF tidak bisa dibuka (rusak atau bukan PDF valid).',
    cause: error,
  );
}
