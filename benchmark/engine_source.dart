import 'package:pdfrx_engine/pdfrx_engine.dart';

import 'package:pdflow/core/pdf_source.dart';
import 'package:pdflow/models/layout.dart';

/// [PdfSource] berbasis pdfrx_engine (pure Dart) — dipakai benchmark/korpus
/// headless (`dart run`), tanpa Flutter. Logika identik dengan
/// lib/core/pdfrx_source.dart (wrapper Flutter).
class EnginePdfSource implements PdfSource {
  EnginePdfSource(this._doc);

  final PdfDocument _doc;

  static Future<EnginePdfSource> open(String path) async {
    return EnginePdfSource(await PdfDocument.openFile(path));
  }

  @override
  int get pageCount => _doc.pages.length;

  @override
  bool get isEncrypted => _doc.isEncrypted;

  @override
  Future<LightPageData> loadLight(int pageIndex) async {
    final raw = await _doc.pages[pageIndex].loadText();
    final fullText = raw?.fullText ?? '';
    final rects = raw?.charRects ?? const [];

    final lineHeights = <double>[];
    var lineStart = 0;
    for (var i = 0; i < fullText.length; i++) {
      if (fullText[i] == '\n') {
        lineHeights.add(_lineBBoxHeight(rects, lineStart, i));
        lineStart = i + 1;
      }
    }
    lineHeights.add(_lineBBoxHeight(rects, lineStart, fullText.length));

    return LightPageData(
      pageIndex: pageIndex,
      charCount: fullText.length,
      lineHeights: lineHeights.where((h) => h > 0).toList(),
    );
  }

  @override
  Future<List<TextSpan>> loadFull(int pageIndex) async {
    final text = await _doc.pages[pageIndex].loadStructuredText();
    final spans = <TextSpan>[];
    for (final f in text.fragments) {
      if (f.text == '\n' || f.text == '\r\n') continue;
      final maxCharH = f.charRects
          .where((r) => r.isNotEmpty)
          .fold<double>(0, (a, r) => r.height > a ? r.height : a);
      spans.add(TextSpan(
        text: f.text,
        xLeft: f.bounds.left,
        xRight: f.bounds.right,
        yBottom: f.bounds.bottom,
        yTop: f.bounds.top,
        fontSize: maxCharH,
      ));
    }
    return spans;
  }

  @override
  Future<void> dispose() => _doc.dispose();

  static double _lineBBoxHeight(List<PdfRect> rects, int start, int end) {
    double minBottom = double.infinity;
    double maxTop = double.negativeInfinity;
    var found = false;
    for (var i = start; i < end && i < rects.length; i++) {
      final r = rects[i];
      if (r.isEmpty) continue;
      if (r.bottom < minBottom) minBottom = r.bottom;
      if (r.top > maxTop) maxTop = r.top;
      found = true;
    }
    return found ? maxTop - minBottom : 0;
  }
}
