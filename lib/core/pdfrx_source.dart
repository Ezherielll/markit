import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../models/layout.dart';
import 'errors.dart';
import 'pdf_source.dart';

/// Implementation of [PdfSource] based on pdfrx (PDFium).
class PdfrxSource implements PdfSource {
  PdfrxSource._(this._doc);

  final PdfDocument _doc;

  /// Open PDF from file. Throws [ConvertException] if corrupt/encrypted.
  static Future<PdfrxSource> open(String path) async {
    try {
      final doc = await PdfDocument.openFile(path);
      return PdfrxSource._(doc);
    } catch (e) {
      throw mapOpenError(e);
    }
  }

  /// Open PDF from bytes (for tests/web).
  static Future<PdfrxSource> openData(Uint8List data, {String sourceName = 'memory'}) async {
    try {
      final doc = await PdfDocument.openData(
        data,
        sourceName: sourceName,
        allowDataOwnershipTransfer: false,
      );
      return PdfrxSource._(doc);
    } catch (e) {
      throw mapOpenError(e);
    }
  }

  /// Fast probe: open, read page count, close (< 2 s).
  static Future<int> probePageCount(String path) async {
    final src = await open(path);
    try {
      return src.pageCount;
    } finally {
      await src.dispose();
    }
  }

  /// Fast probe from bytes (web — without filesystem).
  static Future<int> probePageCountData(Uint8List data) async {
    final src = await openData(data);
    try {
      return src.pageCount;
    } finally {
      await src.dispose();
    }
  }

  @override
  int get pageCount => _doc.pages.length;

  @override
  bool get isEncrypted => _doc.isEncrypted;

  @override
  Future<LightPageData> loadLight(int pageIndex) async {
    final page = _doc.pages[pageIndex];
    final raw = await page.loadText();
    final fullText = raw?.fullText ?? '';
    final rects = raw?.charRects ?? const [];

    // Group rects per line (PDFium inserts \n at line breaks),
    // take line bounding box height — same scale as loadFull.
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
      pageWidth: page.width,
      pageHeight: page.height,
    );
  }

  /// Line bounding box height (maxTop - minBottom) — scale identical to
  /// fragment bounds in [loadFull] (which are word boundingRects).
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

  @override
  Future<List<TextSpan>> loadFull(int pageIndex) async {
    final page = _doc.pages[pageIndex];
    final text = await page.loadStructuredText();
    final spans = <TextSpan>[];
    for (final f in text.fragments) {
      if (f.text == '\n' || f.text == '\r\n') continue;
      final maxCharH = f.charRects
          .where((r) => r.isNotEmpty)
          .fold<double>(0, (a, r) => r.height > a ? r.height : a);
      // Guard: PDFium can return flipped bounds (glyph mirror / rotated text)
      // → without normalize, TextSpan assertion (xLeft<=xRight) crashes.
      final b = normalizeTextSpanBounds(
        left: f.bounds.left,
        right: f.bounds.right,
        bottom: f.bounds.bottom,
        top: f.bounds.top,
      );
      spans.add(
        TextSpan(
          text: f.text,
          xLeft: b.xLeft,
          xRight: b.xRight,
          yBottom: b.yBottom,
          yTop: b.yTop,
          fontSize: maxCharH,
        ),
      );
    }
    return spans;
  }

  @override
  Future<void> dispose() => _doc.dispose();
}
