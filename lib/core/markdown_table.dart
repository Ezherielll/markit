/// Rows → markdown table: first row becomes the header with a `---` separator.
/// Cells escape `|` (markdown table syntax) and newlines (→ space).
String tableToMarkdown(List<List<String>> rows) {
  if (rows.isEmpty) return '';
  final sb = StringBuffer();
  for (var i = 0; i < rows.length; i++) {
    sb.writeln('| ${rows[i].map(_escapeCell).join(' | ')} |');
    if (i == 0) {
      sb.writeln('| ${rows[i].map((_) => '---').join(' | ')} |');
    }
  }
  return sb.toString().trimRight();
}

String _escapeCell(String cell) =>
    cell.replaceAll('|', r'\|').replaceAll('\n', ' ');
