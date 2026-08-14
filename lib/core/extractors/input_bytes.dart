import 'dart:io';
import 'dart:typed_data';

/// Shared bytes loader for extractors: web passes [bytes], the desktop worker
/// reads [path] when [bytes] is null. Null → unreadable input.
Future<Uint8List?> readInputBytes(Uint8List? bytes, String? path) async {
  if (bytes != null && bytes.isNotEmpty) return bytes;
  if (path == null) return null;
  try {
    final file = File(path);
    if (!await file.exists()) return null;
    return await file.readAsBytes();
  } on FileSystemException {
    return null;
  }
}
