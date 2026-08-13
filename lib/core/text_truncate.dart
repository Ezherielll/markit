/// Truncate content for preview — cuts at line boundaries to preserve valid markdown.
/// Returns (preview, whether truncated).
({String preview, bool truncated}) truncateText(
  String content, {
  required int maxChars,
}) {
  if (content.length <= maxChars) {
    return (preview: content, truncated: false);
  }
  var cut = content.lastIndexOf('\n', maxChars);
  if (cut <= 0) cut = maxChars;
  // Cut at line end (including newline) to keep the last line complete.
  if (cut < content.length && content[cut] == '\n') cut++;
  return (
    preview: content.substring(0, cut),
    truncated: true,
  );
}

/// Alias for [truncateText] — legacy name used by markdown preview.
({String preview, bool truncated}) truncateMarkdownPreview(
  String content, {
  required int maxChars,
}) =>
    truncateText(content, maxChars: maxChars);
