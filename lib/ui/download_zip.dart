import 'download_zip_stub.dart'
    if (dart.library.js_interop) 'download_zip_web.dart';

/// Unduh kumpulan file markdown sebagai satu arsip ZIP.
///
/// Web: bangun ZIP di memory (package:archive) → Blob → download.
/// Desktop/IO: no-op — semua output sudah ditulis ke disk oleh FileOutput.
void downloadZipFile(String archiveName, Map<String, String> files) =>
    platformDownloadZipFile(archiveName, files);
