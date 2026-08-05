import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Web: download teks via Blob + anchor (tanpa server).
void platformDownloadTextFile(String fileName, String content) {
  final blob = web.Blob(
    [content.toJS].toJS,
    web.BlobPropertyBag(type: 'text/markdown'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = fileName;
  anchor.click();
  web.URL.revokeObjectURL(url);
}
