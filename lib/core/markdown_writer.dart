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

  /// Jenis blok terakhir yang ditulis; dipakai untuk menekan blank line
  /// di antara baris tabel yang berurutan (mereka satu tabel).
  BlockType? _lastBlockType;

  /// Tulis satu blok; otomatis sisipkan baris kosong antar-blok.
  void writeBlock(Block block) {
    if (_needsBlankLine) {
      // Tidak ada blank line antara baris tabel berurutan (satu tabel).
      // Hanya baris data (tableRow) yang "melanjutkan" tabel; tableHeader baru
      // (tabel kedua / header ulang lintas halaman) harus tetap dipisahkan.
      final isTableContinuation = block.type == BlockType.tableRow &&
          (_lastBlockType == BlockType.tableHeader || _lastBlockType == BlockType.tableRow);
      if (!isTableContinuation) _sink.write('\n');
    }
    switch (block.type) {
      case BlockType.heading:
        _sink.write('${'#' * block.headingLevel} ${_escapeHeadingText(block.text)}\n');
      case BlockType.paragraph:
        _sink.write('${_escapeLine(block.text)}\n');
      case BlockType.listItem:
      case BlockType.unorderedListItem:
        // Fase C: 2 spasi indent per level nested.
        final indent = '  ' * block.listDepth;
        _sink.write('$indent- ${_escapeLine(block.text)}\n');
      case BlockType.orderedListItem:
        final indent = '  ' * block.listDepth;
        final idx = block.listIndex ?? 1;
        _sink.write('$indent$idx. ${_escapeLine(block.text)}\n');
      case BlockType.tableHeader:
        // Fase C: baris header + separator. Sel tidak di posisi awal baris,
        // jadi escaping line-start (mis. "2.50" → "\2.50") tidak berlaku.
        final cells = block.cells ?? [block.text];
        _sink.write('| ${cells.map(_escapeHeadingText).join(' | ')} |\n');
        _sink.write('| ${cells.map((_) => '---').join(' | ')} |\n');
      case BlockType.tableRow:
        // Fase C: baris data (tanpa separator).
        final cells = block.cells ?? [block.text];
        _sink.write('| ${cells.map(_escapeHeadingText).join(' | ')} |\n');
    }
    _lastBlockType = block.type;
    // Blank line tetap dibutuhkan setelah blok apa pun — termasuk setelah
    // tabel selesai; blank line di tengah tabel ditekan via _lastBlockType.
    _needsBlankLine = true;
  }

  /// Tulis konten mentah (passthrough markdown, code block, tabel markdown)
  /// dengan pemisah baris kosong yang sama seperti [writeBlock].
  void writeRaw(String raw) {
    if (_needsBlankLine) {
      _sink.write('\n');
    }
    _sink.write(raw);
    if (!raw.endsWith('\n')) {
      _sink.write('\n');
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

  /// Escaping teks heading: angka+'.' tidak perlu di-escape (sudah di dalam
  /// prefix '#'), hanya '#' di awal teks yang bisa mengubah struktur.
  String _escapeHeadingText(String text) {
    var result = text;
    if (result.startsWith('#')) {
      result = '\\$result';
    }
    result = result.replaceAll('`', r'\`');
    return result;
  }

  /// Flush buffer ke disk (dipanggil per halaman oleh converter).
  Future<void> flush() => _sink.flush();

  /// Tutup sink (setelah semua halaman ditulis).
  Future<void> close() => _sink.close();
}
