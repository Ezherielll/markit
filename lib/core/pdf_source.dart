import '../models/layout.dart';
import 'errors.dart';

/// Compact page data for pass 1 (font histogram).
class LightPageData {
  LightPageData({
    required this.pageIndex,
    required this.charCount,
    required this.lineHeights,
    this.pageWidth = 0,
    this.pageHeight = 0,
  });

  final int pageIndex;
  final int charCount;

  /// Maximum line bbox height (fontSize proxy, SAME scale
  /// as [PdfrxSource.loadFull] — line height, not x-height).
  /// Basis for body font histogram.
  final List<double> lineHeights;

  /// Page width (MediaBox) in PDF units; 0 if unavailable.
  final double pageWidth;

  /// Page height (MediaBox) in PDF units; 0 if unavailable.
  final double pageHeight;

  bool get hasText => charCount > 0;
}

/// PDF source abstraction (pure Dart).
///
/// Concrete implementation: [PdfrxSource] (pdfrx/PDFium).
/// Injected to allow pipeline testing with fake sources without PDF files.
abstract class PdfSource {
  int get pageCount;

  /// Whether the PDF is password-protected.
  bool get isEncrypted;

  /// Pass 1: read raw text + char height only (without detailed layout).
  /// [pageIndex] 0-based.
  Future<LightPageData> loadLight(int pageIndex);

  /// Pass 2: read positioned text spans (words + bbox + proxy fontSize).
  /// [pageIndex] 0-based.
  Future<List<TextSpan>> loadFull(int pageIndex);

  Future<void> dispose();
}

/// General error mapping helper.
ConvertException mapOpenError(Object error) {
  // pdfrx: Password-protected PDF is thrown as PdfPasswordException
  // (including random bytes interpreted by PDFium as encrypted).
  final name = error.runtimeType.toString();
  if (name.contains('Password')) {
    return ConvertException(
      ConvertError.encrypted,
      'Password-protected PDF is not supported.',
      cause: error,
    );
  }
  return ConvertException(
    ConvertError.corrupt,
    'PDF cannot be opened (corrupt or invalid PDF file).',
    cause: error,
  );
}
