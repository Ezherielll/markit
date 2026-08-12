import '../models/layout.dart';
import 'column_splitter.dart';
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
    required this.profile,
    required this.elapsed,
  });

  /// Path file output (desktop/FileOutput); null untuk MemoryOutput (web).
  final String? outputPath;

  final int pageCount;

  /// Halaman yang gagal diekstrak (FR-10c) — index 0-based.
  final List<int> failedPages;

  /// Profil dokumen hasil pass 1 (Fase B: pengganti DocStats).
  final DocProfile profile;
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

  /// State cross-page untuk hiphenasi (Fase C).
  ///
  /// Nantinya (Fase D) menyimpan teks baris terakhir halaman yang baru
  /// selesai diproses, untuk di-cek di awal halaman berikutnya apakah kata
  /// terpenggal ("word-" + "rest") harus disambung.
  /// LIMITASI: koreksi cross-page membutuhkan output buffering (tidak bisa
  /// undo write yang sudah terjadi) — defer ke Fase D. Di Fase C state ini
  /// hanya dideklarasikan, belum diisi/dibaca (deteksi lanjutan di Fase D).
  // ignore: unused_field — placeholder cross-page state (Fase D)
  String? _lastPageLastLineText;

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

    final profile = await DocStatsComputer(source).computeProfile();

    if (profile.likelyScanned) {
      throw ConvertException(
        ConvertError.noText,
        'Dokumen tampaknya hasil scan — tanpa OCR, hasil akan kosong.',
      );
    }

    final failedPages = <int>[];
    final sink = await output.openSink();
    final writer = MarkdownWriter(sink);
    final pipeline = (
      writer: writer,
      columnSplitter: const ColumnSplitter(), // Fase B
      grouper: LineGrouper(config: config, profile: profile), // Fase B
      joiner: ParagraphJoiner(config: config),
      classifier: StructureClassifier.withProfile(
        profile: profile,
        config: config,
      ),
      profile: profile,
      // Batas zona header/footer dari profil + config (Fase B)
      headerBottom: profile.pageHeight * config.headerZoneFraction,
      footerTop: profile.pageHeight * config.footerZoneFraction,
    );

    var cancelled = false;
    try {
      for (var i = 0; i < source.pageCount; i++) {
        if (isCancelled != null && isCancelled()) {
          cancelled = true;
          break;
        }

        final List<TextSpan> rawSpans;
        try {
          rawSpans = await source.loadFull(i);
        } catch (e) {
          failedPages.add(i);
          continue;
        }

        await _convertPage(rawSpans, pipeline);

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
      profile: profile,
      elapsed: sw.elapsed,
    );
  }

  /// Proses spans satu halaman: filter header/footer → split kolom →
  /// line grouping → paragraph join → klasifikasi → write (streaming).
  Future<void> _convertPage(List<TextSpan> rawSpans, _PagePipeline pipeline) async {
    final profile = pipeline.profile;
    // Fase B: filter header/footer spans sebelum processing
    // Header: yTop > headerBottom; Footer: yTop < footerTop
    final spans = profile.pageHeight > 0
        ? rawSpans
            .where((s) => s.yTop <= pipeline.headerBottom &&
                s.yTop >= pipeline.footerTop)
            .toList()
        : rawSpans;

    // Fase B: split ke kolom, proses per kolom (reading order kiri→kanan)
    final columns = pipeline.columnSplitter.split(spans, profile);
    for (final columnSpans in columns) {
      final lines = pipeline.grouper.group(columnSpans);
      final paragraphs = pipeline.joiner.join(
        lines,
        isHeading: pipeline.classifier.isHeading,
      );
      final blocks = pipeline.classifier.classify(paragraphs);
      for (final block in blocks) {
        pipeline.writer.writeBlock(block);
      }
    }
    await pipeline.writer.flush();
  }
}

/// Pipeline pass 2 yang dipakai bersama untuk semua halaman (konstruksi
/// sekali di [Converter.convert], dibagi antar panggilan [_convertPage]).
typedef _PagePipeline = ({
  MarkdownWriter writer,
  ColumnSplitter columnSplitter,
  LineGrouper grouper,
  ParagraphJoiner joiner,
  StructureClassifier classifier,
  DocProfile profile,
  double headerBottom,
  double footerTop,
});

class _CancelledException implements Exception {
  const _CancelledException();
}
