import 'download_text_stub.dart'
    if (dart.library.js_interop) 'download_text_web.dart';

/// Download text as a .md file.
///
/// Web: triggers browser download via Blob + anchor.
/// Desktop/IO: no-op — output is written directly to disk by FileOutput.
void downloadTextFile(String fileName, String content) =>
    platformDownloadTextFile(fileName, content);
