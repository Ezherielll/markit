import 'dart:typed_data';

import 'package:pdfrx/pdfrx.dart';

import '../models/layout.dart';
import 'errors.dart';
import 'pdf_source.dart';

/// Implementasi [PdfSource] berbasis pdfrx (PDFium).
class PdfrxSource implements PdfSource {
  PdfrxSource._(this._doc);

  final PdfDocument _doc;

  /// Buka PDF dari file. Melempar [ConvertException] bila corrupt/encrypted.
  static Future<PdfrxSource> open(String path) async {
    try {
      final doc = await PdfDocument.openFile(path);
      return PdfrxSource._(doc);
    } catch (e) {
      throw mapOpenError(e);
    }
  }

  /// Buka PDF dari bytes (untuk test).
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

  /// Probe cepat: buka, baca jumlah halaman, tutup (FR-01, < 2 s).
  static Future<int> probePageCount(String path) async {
    final src = await open(path);
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

    // Group rects per baris (PDFium memasukkan \n pada line break),
    // ambil tinggi bounding box tiap baris — skala sama dengan loadFull.
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

  /// Tinggi bounding box baris (maxTop - minBottom) — skala identik dengan
  /// bounds fragment pada [loadFull] (yang merupakan boundingRect kata).
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
      spans.add(
        TextSpan(
          text: f.text,
          xLeft: f.bounds.left,
          xRight: f.bounds.right,
          yBottom: f.bounds.bottom,
          yTop: f.bounds.top,
          fontSize: maxCharH,
        ),
      );
    }
    return spans;
  }

  @override
  Future<void> dispose() => _doc.dispose();
}
