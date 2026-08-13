import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markit/ui/source/source_loader.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:pdfrx/pdfrx.dart';

/// PDF source viewer: rendered pages via PdfViewer (pdfrx).
///
/// Desktop: [PdfViewer.file] (disk file); web: [PdfViewer.data] (in-memory bytes).
/// Encrypted PDFs are not supported (requires password input).
class PdfSourceView extends StatelessWidget {
  const PdfSourceView({super.key, required this.data, required this.name});

  final SourcePdf data;

  /// File name — used by [PdfViewer.data] as `sourceName` (unique source identifier
  /// in pdfrx cache).
  final String name;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final viewer = kIsWeb
        ? PdfViewer.data(data.bytes!, sourceName: name, params: _params(isDark))
        : PdfViewer.file(data.path!, params: _params(isDark));
    return viewer;
  }

  PdfViewerParams _params(bool isDark) => PdfViewerParams(
    backgroundColor: isDark ? MarkitColors.paperDark : MarkitColors.paperLight,
    margin: 16,
    pageDropShadow: const BoxShadow(blurRadius: 8, offset: Offset(0, 2)),
  );
}
