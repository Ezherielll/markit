import 'dart:io';

/// Abstract sink untuk output markdown — memisahkan "menulis" dari media
/// (file di desktop vs memory di web). Menggantikan IOSink langsung agar
/// pipeline inti bebas `dart:io`.
abstract class MdSink {
  void write(String data);
  Future<void> flush();
  Future<void> close();
}

/// Sink berbasis file (desktop).
class FileMdSink implements MdSink {
  FileMdSink(this._sink);

  final IOSink _sink;

  @override
  void write(String data) => _sink.write(data);

  @override
  Future<void> flush() => _sink.flush();

  @override
  Future<void> close() => _sink.close();
}

/// Sink berbasis memory (web) — menulis ke [StringBuffer].
class MemoryMdSink implements MdSink {
  MemoryMdSink(this._buffer);

  final StringBuffer _buffer;

  @override
  void write(String data) => _buffer.write(data);

  @override
  Future<void> flush() async {}

  @override
  Future<void> close() async {}
}

/// Target output konversi. [Converter] membuka sink via [openSink],
/// lalu memanggil [commit] (sukses) atau [abort] (cancel/gagal).
abstract class OutputTarget {
  Future<MdSink> openSink();

  /// Finalisasi sukses: pindahkan partial → output final.
  Future<void> commit();

  /// Bersihkan saat cancel/gagal (hapus partial bila ada).
  Future<void> abort();
}

/// Output ke file (desktop). Mempertahankan semantik `.partial` + rename
/// (D7): tulis ke `outputPath.partial`, rename saat [commit], hapus saat
/// [abort] / cancel.
class FileOutput implements OutputTarget {
  FileOutput(this.outputPath);

  final String outputPath;

  String get partialPath => '$outputPath.partial';

  @override
  Future<MdSink> openSink() async {
    return FileMdSink(File(partialPath).openWrite());
  }

  @override
  Future<void> commit() async {
    final target = File(outputPath);
    if (await target.exists()) {
      await target.delete();
    }
    await File(partialPath).rename(outputPath);
  }

  @override
  Future<void> abort() async {
    final partial = File(partialPath);
    if (await partial.exists()) {
      await partial.delete();
    }
  }
}

/// Output ke memory (web) — hasil konversi bisa dibaca via [content]
/// setelah [commit]. Tidak ada filesystem.
class MemoryOutput implements OutputTarget {
  final StringBuffer _buffer = StringBuffer();

  /// Isi markdown setelah konversi sukses.
  String get content => _buffer.toString();

  @override
  Future<MdSink> openSink() async => MemoryMdSink(_buffer);

  @override
  Future<void> commit() async {}

  @override
  Future<void> abort() async {}
}
