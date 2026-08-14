import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Build a synthetic ZIP from a name → content map (test fixtures).
Uint8List buildZip(Map<String, String> entries) {
  final archive = Archive();
  for (final e in entries.entries) {
    archive.addFile(ArchiveFile.string(e.key, e.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
