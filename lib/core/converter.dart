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

/// Conversion result.
class ConversionResult {
  ConversionResult({
    required this.outputPath,
    required this.pageCount,
    required this.failedPages,
    required this.profile,
    required this.elapsed,
  });

  /// Output file path (desktop/FileOutput); null for MemoryOutput (web).
  final String? outputPath;

  final int pageCount;

  /// Pages that failed extraction — 0-based indices.
  final List<int> failedPages;

  /// Document profile resulting from pass 1.
  final DocProfile profile;
  final Duration elapsed;

  bool get hasFailures => failedPages.isNotEmpty;
}

/// Progress per page.
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

/// Orchestrator for two-pass pipeline + streaming write.
///
/// Pass 1: [DocStatsComputer] — lightweight histogram profile.
/// Pass 2: per page → line grouping → paragraph → classification → write.
/// Output is written to [OutputTarget] (FileOutput desktop / MemoryOutput web);
/// atomic `.partial` + rename semantics handled by target.
class Converter {
  Converter({PipelineConfig? config})
      : config = config ?? const PipelineConfig();

  final PipelineConfig config;

  /// Execute conversion.
  ///
  /// [source] opened by caller; [onProgress] invoked per page;
  /// [isCancelled] checked per page. Throws [ConvertException]
  /// if total conversion fails; page-level failure recorded in [ConversionResult.failedPages].
  Future<ConversionResult> convert({
    required PdfSource source,
    required OutputTarget output,
    void Function(ConversionProgress progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final sw = Stopwatch()..start();

    if (source.pageCount == 0) {
      throw ConvertException(ConvertError.corrupt, 'PDF has no pages.');
    }

    final profile = await DocStatsComputer(source).computeProfile();

    if (profile.likelyScanned) {
      throw ConvertException(
        ConvertError.noText,
        'Document appears to be scanned — without OCR, output will be empty.',
      );
    }

    final failedPages = <int>[];
    final sink = await output.openSink();
    final writer = MarkdownWriter(sink);
    // Cross-page state (O(1)) — single held block + open table flag
    // (used for repeated header dropping across pages).
    final crossPage = _CrossPageState();
    final pipeline = (
      writer: writer,
      columnSplitter: const ColumnSplitter(),
      grouper: LineGrouper(config: config, profile: profile),
      joiner: ParagraphJoiner(config: config),
      classifier: StructureClassifier.withProfile(
        profile: profile,
        config: config,
      ),
      profile: profile,
      // Header/footer zone bounds from profile + config
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
      // Flush last pending block — final block of conversion written at the end.
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

  /// Process spans for a single page: filter header/footer → split columns →
  /// line grouping → paragraph join → classification → streaming write.
  Future<void> _convertPage(
    List<TextSpan> rawSpans,
    _PagePipeline pipeline,
    _CrossPageState crossPage,
  ) async {
    final profile = pipeline.profile;
    // Filter header/footer spans before processing
    // Header: yTop > headerBottom; Footer: yTop < footerTop
    final spans = profile.pageHeight > 0
        ? rawSpans
            .where((s) => s.yTop <= pipeline.headerBottom &&
                s.yTop >= pipeline.footerTop)
            .toList()
        : rawSpans;

    // Split into columns, process per column (reading order left→right)
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

  /// Process classified blocks for a column — cross-page tables
  /// (dropping repeated headers) + holding the last block (pending block, O(1)).
  ///
  /// Order: (0) flush held block from previous page/column with cross-page hyphenation merge →
  /// (a) drop REPEATED header on continuation pages → (b) write all blocks except last,
  /// hold the last → (c) update table flags from held block.
  void _postClassifyBlocks(
    List<Block> blocks,
    MarkdownWriter writer,
    _CrossPageState state,
  ) {
    // (0) Flush held block from previous page/column with cross-page hyphenation merge.
    //     Blocks written in (0) are NOT counted toward table state.
    blocks = _flushPending(state, writer, blocks);

    // (a) Cross-page tables: REPEATED headers on continuation pages are DROPPED
    //     (common printing pattern: each page repeats table header).
    //     ONLY headers with EXACT content matching the currently open table header
    //     ([state.openTableHeader]) are dropped — new valid table headers
    //     (different content) on subsequent pages are preserved.
    if (state.tableOpen && state.openTableHeader != null) {
      final repeated = _dropRepeatedHeader(blocks, state.openTableHeader!);
      if (repeated != null) {
        blocks = [...blocks]..remove(repeated);
        state.openTableHeader = repeated.text;
      }
    }

    // (b) Write all blocks except the last; the last block is held
    //     (used for cross-page hyphenation correction). Headers WRITTEN
    //     are recorded as open table headers for the next page.
    if (blocks.isNotEmpty) {
      for (final b in blocks.take(blocks.length - 1)) {
        writer.writeBlock(b);
        if (b.type == BlockType.tableHeader) {
          state.openTableHeader = b.text;
        }
      }
      state.pendingBlock = blocks.last;
    }

    // (c) Table state for next page — determined by the last held block;
    //     pages without blocks retain previous state.
    if (blocks.isNotEmpty) {
      _updateCrossPageTable(state);
    }
  }

  /// Flush held block from previous page/column: test cross-page hyphenation merge
  /// with the first block of this page; if mergeable, replace first block with merged result
  /// (pending is NOT written separately), otherwise write pending as-is.
  /// Returns block list for further processing.
  List<Block> _flushPending(
    _CrossPageState state,
    MarkdownWriter writer,
    List<Block> blocks,
  ) {
    final pending = state.pendingBlock;
    if (pending == null) return blocks;
    state.pendingBlock = null;
    final merged = blocks.isEmpty
        ? null
        : _tryMergeCrossPage(pending, blocks.first);
    if (merged != null) {
      return [merged, ...blocks.skip(1)];
    }
    writer.writeBlock(pending);
    return blocks;
  }

  /// Merge cross-page paragraphs split by hyphen.
  /// Rule (consistent with ParagraphJoiner): block A ends with '-' AND block B (paragraph)
  /// starts with [a-z] → merge without '-'. Returns null if conditions not met.
  Block? _tryMergeCrossPage(Block a, Block b) {
    if (a.type != BlockType.paragraph || b.type != BlockType.paragraph) {
      return null;
    }
    final textA = a.text.trimRight();
    if (!textA.endsWith('-') || textA.length < 2) return null;
    final textB = b.text.trimLeft();
    if (textB.isEmpty || !RegExp(r'^[a-z]').hasMatch(textB)) return null;
    return Block(
      type: BlockType.paragraph,
      lines: ['${textA.substring(0, textA.length - 1)}$textB'],
    );
  }

  /// Find REPEATED table header (matching content [openHeader]) appearing before
  /// any data row on this page; null if none.
  /// Search tolerates preceding elements (e.g. repeated titles becoming headings).
  Block? _dropRepeatedHeader(List<Block> blocks, String openHeader) {
    final headerIdx = blocks.indexWhere((b) => b.type == BlockType.tableHeader);
    if (headerIdx == -1 || blocks[headerIdx].text != openHeader) {
      return null;
    }
    final rowIdx = blocks.indexWhere((b) => b.type == BlockType.tableRow);
    if (rowIdx != -1 && headerIdx >= rowIdx) {
      return null;
    }
    return blocks[headerIdx];
  }

  /// Update cross-page state from held block: tableHeader → update open table header;
  /// tableRow → table continues (header preserved); other block → table ends, state cleared.
  void _updateCrossPageTable(_CrossPageState state) {
    final held = state.pendingBlock!;
    if (held.type == BlockType.tableHeader) {
      state.openTableHeader = held.text;
      state.tableOpen = true;
    } else if (held.type == BlockType.tableRow) {
      state.tableOpen = true;
    } else {
      state.tableOpen = false;
      state.openTableHeader = null;
    }
  }
}

/// Shared pass 2 pipeline used across all pages (constructed once in
/// [Converter.convert], shared across [_convertPage] calls).
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

/// Cross-page state (O(1)): last block held from previous page + open table flag +
/// open table header text (dropped only if content matches).
class _CrossPageState {
  Block? pendingBlock;
  bool tableOpen = false;

  /// Open table header text; null if no table open. Populated when
  /// tableHeader is PROCESSED (written or dropped).
  String? openTableHeader;
}

class _CancelledException implements Exception {
  const _CancelledException();
}
