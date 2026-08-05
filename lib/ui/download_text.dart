import 'download_text_stub.dart'
    if (dart.library.js_interop) 'download_text_web.dart';

/// Unduh teks sebagai file .md.
///
/// Web: trigger browser download via Blob + anchor.
/// Desktop/IO: no-op — output sudah ditulis ke disk oleh FileOutput.
void downloadTextFile(String fileName, String content) =>
    platformDownloadTextFile(fileName, content);
