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
    // Fase D: state lintas halaman (O(1)) — satu blok tertahan + flag
    // tabel terbuka (dipakai drop header berulang lintas halaman).
    final crossPage = _CrossPageState();
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

        await _convertPage(rawSpans, pipeline, crossPage);

        onProgress?.call(ConversionProgress(
          page: i + 1,
          total: source.pageCount,
          elapsed: sw.elapsed,
        ));
      }
      if (!cancelled && isCancelled != null && isCancelled()) {
        cancelled = true;
      }
      // Fase D: flush blok terakhir yang ditahan (pending block) — satu
      // blok terakhir per halaman baru ditulis di akhir konversi.
      if (crossPage.pendingBlock != null) {
        writer.writeBlock(crossPage.pendingBlock!);
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
  Future<void> _convertPage(
    List<TextSpan> rawSpans,
    _PagePipeline pipeline,
    _CrossPageState crossPage,
  ) async {
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
      _postClassifyBlocks(blocks, pipeline.writer, crossPage);
    }
    await pipeline.writer.flush();
  }

  /// Fase D: proses blok hasil klasifikasi satu kolom — tabel lintas halaman
  /// (drop header berulang) + penahanan blok terakhir (pending block, O(1)).
  ///
  /// Urutan: (0) flush blok yang ditahan halaman/kolom sebelumnya (penahanan
  /// hanya menunda SATU blok — output akhir identik) → (a) drop header
  /// BERULANG di halaman lanjutan → (b) tulis semua blok kecuali terakhir,
  /// tahan yang terakhir → (c) perbarui flag tabel dari blok yang ditahan.
  /// Task 6 menyisipkan merge hiphenasi lintas halaman antara (0) dan (a)
  /// di helper ini (convert() tetap di bawah gate cognitive complexity).
  void _postClassifyBlocks(
    List<Block> blocks,
    MarkdownWriter writer,
    _CrossPageState state,
  ) {
    // (0) Tulis blok yang ditahan dari halaman/kolom sebelumnya. Tanpa ini
    //     pending block dari halaman antara hilang (hanya blok terakhir
    //     konversi yang terflush) — output tidak identik dengan sebelum
    //     Fase D.
    if (state.pendingBlock != null) {
      writer.writeBlock(state.pendingBlock!);
      state.pendingBlock = null;
    }

    // (a) Tabel lintas halaman: header BERULANG di halaman lanjutan DIBUANG
    //     (pola cetak umum: tiap halaman mengulang header). Demote ke baris
    //     data SALAH — string '| Name | Qty | Price |' akan muncul 2x dan
    //     baris duplikat mencemari isi tabel.
    //     Pencarian menoleransi elemen sebelum header (mis. judul berulang
    //     yang menjadi heading) — syaratnya header muncul sebelum baris data
    //     mana pun di halaman ini (header "baru" untuk tabel baru yang sah
    //     tetap dipertahankan).
    if (state.tableOpen && blocks.isNotEmpty) {
      final headerIdx = blocks.indexWhere((b) => b.type == BlockType.tableHeader);
      if (headerIdx != -1) {
        final rowIdx = blocks.indexWhere((b) => b.type == BlockType.tableRow);
        if (rowIdx == -1 || headerIdx < rowIdx) {
          blocks = [...blocks]..removeAt(headerIdx);
        }
      }
    }

    // (b) Tulis semua blok kecuali yang terakhir; blok terakhir ditahan
    //     (dipakai koreksi hiphenasi lintas halaman di Task 6).
    if (blocks.isNotEmpty) {
      for (final b in blocks.take(blocks.length - 1)) {
        writer.writeBlock(b);
      }
      state.pendingBlock = blocks.last;
    }

    // (c) Flag tabel untuk halaman berikutnya — blok terakhir yang ditahan
    //     menentukan; halaman tanpa blok mempertahankan state lama.
    if (blocks.isNotEmpty) {
      final held = state.pendingBlock!;
      state.tableOpen =
          held.type == BlockType.tableRow || held.type == BlockType.tableHeader;
    }
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

/// State lintas halaman Fase D (O(1)): blok terakhir yang ditahan dari
/// halaman sebelumnya + flag tabel terbuka (drop header berulang).
class _CrossPageState {
  Block? pendingBlock;
  bool tableOpen = false;
}

class _CancelledException implements Exception {
  const _CancelledException();
}
