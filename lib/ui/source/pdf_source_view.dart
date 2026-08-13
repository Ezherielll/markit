import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markit/ui/source/source_loader.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:pdfrx/pdfrx.dart';

/// Tampilan PDF sumber: halaman ter-render via PdfViewer (pdfrx).
///
/// Desktop: [PdfViewer.file] (file di disk); web: [PdfViewer.data] (bytes
/// di memory). PDF ter-enkripsi tidak didukung (butuh input password).
class PdfSourceView extends StatelessWidget {
  const PdfSourceView({super.key, required this.data, required this.name});

  final SourcePdf data;

  /// Nama file — dipakai [PdfViewer.data] sebagai `sourceName` (identitas
  /// unik sumber di cache pdfrx).
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
    backgroundColor: isDark ? PdflowColors.paperDark : PdflowColors.paperLight,
    margin: 16,
    pageDropShadow: const BoxShadow(blurRadius: 8, offset: Offset(0, 2)),
  );
}
