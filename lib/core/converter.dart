import '../models/layout.dart';
import 'doc_stats.dart';
import 'errors.dart';
import 'line_grouper.dart';
import 'markdown_writer.dart';
import 'output.dart';
import 'paragraph_joiner.dart';
import 'pdf_source.dart';
import 'structure_classifier.dart';

/// Hasil akhir konversi.
class ConversionResult {
  ConversionResult({
    required this.outputPath,
    required this.pageCount,
    required this.failedPages,
    required this.stats,
    required this.elapsed,
  });

  /// Path file output (desktop/FileOutput); null untuk MemoryOutput (web).
  final String? outputPath;

  final int pageCount;

  /// Halaman yang gagal diekstrak (FR-10c) — index 0-based.
  final List<int> failedPages;

  final DocStats stats;
  final Duration elapsed;

  bool get hasFailures => failedPages.isNotEmpty;
}

/// Progress per halaman.
class ConversionProgress {
  ConversionProgress({
    required this.page,
    required this.total,
    required this.elapsed,
  });

  final int page;
  final int total;
  final Duration elapsed;
}

/// Orkestrasi pipeline dua-pass (D5) + streaming write (FR-02/07).
///
/// Pass 1: [DocStatsComputer] — histogram ringan, bukan layout penuh.
/// Pass 2: per halaman → line grouping → paragraph → klasifikasi → write.
/// Output ditulis ke [OutputTarget] (FileOutput desktop / MemoryOutput web);
/// semantik `.partial` + rename ditangani target (D7).
class Converter {
  Converter({PipelineConfig? config})
      : config = config ?? const PipelineConfig();

  final PipelineConfig config;

  /// Jalankan konversi.
  ///
  /// [source] dibuka oleh caller; [onProgress] dipanggil per halaman;
  /// [isCancelled] dicek per halaman (FR-11). Melempar [ConvertException]
  /// bila total gagal; page-level failure dicatat di [ConversionResult.failedPages].
  Future<ConversionResult> convert({
    required PdfSource source,
    required OutputTarget output,
    void Function(ConversionProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sw = Stopwatch()..start();

    if (source.pageCount == 0) {
      throw ConvertException(ConvertError.corrupt, 'PDF tidak punya halaman.');
    }

    final stats = await DocStatsComputer(source).compute();

    if (stats.likelyScanned) {
      throw ConvertException(
        ConvertError.noText,
        'Dokumen tampaknya hasil scan — tanpa OCR, hasil akan kosong.',
      );
    }

    final failedPages = <int>[];
    final sink = await output.openSink();
    final writer = MarkdownWriter(sink);
    final grouper = LineGrouper(config: config);
    final joiner = ParagraphJoiner(config: config);
    final classifier = StructureClassifier(
      bodyFontSize: stats.bodyFontSize,
      config: config,
    );

    var cancelled = false;
    try {
      for (var i = 0; i < source.pageCount; i++) {
        if (isCancelled != null && isCancelled()) {
          cancelled = true;
          break;
        }

        final List<TextSpan> spans;
        try {
          spans = await source.loadFull(i);
        } catch (e) {
          failedPages.add(i);
          continue;
        }

        final lines = grouper.group(spans);
        final paragraphs = joiner.join(
          lines,
          isHeading: classifier.isHeading,
        );
        final blocks = classifier.classify(paragraphs);
        for (final block in blocks) {
          writer.writeBlock(block);
        }
        await writer.flush();

        onProgress?.call(ConversionProgress(
          page: i + 1,
          total: source.pageCount,
          elapsed: sw.elapsed,
        ));
      }
      if (!cancelled && isCancelled != null && isCancelled()) {
        cancelled = true;
      }
    } finally {
      await writer.close();
    }

    if (cancelled) {
      await output.abort();
      throw const _CancelledException();
    }

    await output.commit();

    return ConversionResult(
      outputPath: output is FileOutput ? output.outputPath : null,
      pageCount: source.pageCount,
      failedPages: failedPages,
      stats: stats,
      elapsed: sw.elapsed,
    );
  }
}

class _CancelledException implements Exception {
  const _CancelledException();
}
