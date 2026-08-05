import '../models/layout.dart';
import 'output.dart';

/// Stage 5: render blok → markdown, ditulis streaming (FR-07).
///
/// Konvensi (D8): UTF-8 tanpa BOM, line ending `\n`.
/// Menulis langsung ke [MdSink] per blok — caller mengelola sink/flush
/// (streaming per halaman). Escaping ringan agar output valid markdown.
class MarkdownWriter {
  MarkdownWriter(this._sink);

  final MdSink _sink;
  bool _needsBlankLine = false;

  /// Tulis satu blok; otomatis sisipkan baris kosong antar-blok.
  void writeBlock(Block block) {
    if (_needsBlankLine) {
      _sink.write('\n');
    }
    switch (block.type) {
      case BlockType.heading:
        _sink.write('${'#' * block.headingLevel} ${_escapeLine(block.text)}\n');
      case BlockType.paragraph:
        _sink.write('${_escapeLine(block.text)}\n');
      case BlockType.listItem:
        _sink.write('- ${_escapeLine(block.text)}\n');
    }
    _needsBlankLine = true;
  }

  /// Escaping ringan: karakter di awal baris yang mengubah struktur markdown.
  String _escapeLine(String text) {
    final trimmed = text;
    var result = trimmed;
    if (result.startsWith('#') ||
        result.startsWith('>') ||
        result.startsWith('-') ||
        result.startsWith('*') ||
        result.startsWith('+') ||
        RegExp(r'^\d+\.').hasMatch(result)) {
      result = '\\$result';
    }
    // Backtick tunggal bisa menutup inline code.
    result = result.replaceAll('`', r'\`');
    return result;
  }

  /// Flush buffer ke disk (dipanggil per halaman oleh converter).
  Future<void> flush() => _sink.flush();

  /// Tutup sink (setelah semua halaman ditulis).
  Future<void> close() => _sink.close();
}
