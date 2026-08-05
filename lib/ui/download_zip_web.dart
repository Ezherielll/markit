import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:web/web.dart' as web;

/// Web: bangun ZIP (package:archive) dari [files] lalu download via Blob.
void platformDownloadZipFile(String archiveName, Map<String, String> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile.string(entry.key, entry.value));
  }
  final bytes = Uint8List.fromList(ZipEncoder().encode(archive));

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/zip'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = archiveName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
