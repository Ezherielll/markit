/// Tipe error konversi (FR-10). Pure Dart.
library;

enum ConvertError {
  /// File tidak bisa dibuka/dibaca sama sekali.
  corrupt,

  /// PDF dilindungi password (tidak didukung MVP).
  encrypted,

  /// Tidak ada teks yang bisa diekstrak (indikasi hasil scan, tanpa OCR).
  noText,

  /// Satu halaman atau lebih gagal diekstrak (konversi tetap lanjut).
  pageFailed,
}

class ConvertException implements Exception {
  ConvertException(this.type, this.message, {this.cause});

  final ConvertError type;
  final String message;
  final Object? cause;

  @override
  String toString() => 'ConvertException($type): $message';
}
