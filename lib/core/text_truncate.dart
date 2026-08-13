/// Potong konten untuk preview — memotong di batas baris agar markdown tetap
/// valid. Return (preview, apakah terpotong).
({String preview, bool truncated}) truncateText(
  String content, {
  required int maxChars,
}) {
  if (content.length <= maxChars) {
    return (preview: content, truncated: false);
  }
  var cut = content.lastIndexOf('\n', maxChars);
  if (cut <= 0) cut = maxChars;
  // Potong di akhir baris (termasuk newline) agar baris terakhir utuh.
  if (cut < content.length && content[cut] == '\n') cut++;
  return (
    preview: content.substring(0, cut),
    truncated: true,
  );
}

/// Alias [truncateText] — nama historis yang dipakai preview markdown
/// (diduplikasi dari lib/ui/widgets/markdown_helpers.dart agar caller lama
/// tidak berubah).
({String preview, bool truncated}) truncateMarkdownPreview(
  String content, {
  required int maxChars,
}) =>
    truncateText(content, maxChars: maxChars);
