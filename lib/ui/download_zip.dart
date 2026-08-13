import 'download_zip_stub.dart'
    if (dart.library.js_interop) 'download_zip_web.dart';

/// Download collection of markdown files as a single ZIP archive.
///
/// Web: builds ZIP in memory (package:archive) → Blob → download.
/// Desktop/IO: no-op — all outputs are written directly to disk by FileOutput.
void downloadZipFile(String archiveName, Map<String, String> files) =>
    platformDownloadZipFile(archiveName, files);
