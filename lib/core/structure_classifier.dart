import '../models/layout.dart';
import 'doc_stats.dart';
import 'table_detector.dart';

/// Stage 4: structure classification (heading, list, table).
///
/// Multi-level heading based on [DocProfile.headingBands]
/// (font size band → H1..H4 level); fallback heading factor
/// when profile is unavailable. Pattern-based list detection:
/// bullet must be followed by whitespace ('o' is not a bullet), ordered list
/// `1.` / `1)` / `a.` / `a)` supported.
/// [TableDetector] tags paragraphs first (table group →
/// BlockType.tableHeader/tableRow); nested list via [DocProfile.bodyLeftMargin]
/// (xLeft ladder → listDepth 0..3, step 1.5 * bodyFontSize).
class StructureClassifier {
  StructureClassifier({
    required this.bodyFontSize,
    this.config = const PipelineConfig(),
    this._profile,
  });

  /// Main factory: pass 1 profile with heading bands.
  StructureClassifier.withProfile({
    required DocProfile profile,
    PipelineConfig? config,
  }) : this(
          bodyFontSize: profile.bodyFontSize,
          config: config ?? const PipelineConfig(),
          profile: profile,
        );

  final double bodyFontSize;
  final PipelineConfig config;

  /// Pass 1 profile (optional, backward compatibility) for multi-band heading.
  final DocProfile? _profile;

  /// Table detector (stateless, safe as singleton).
  final TableDetector _tableDetector = const TableDetector();

  /// Bullet must be followed by whitespace — avoids false positives
  /// like '-3°C' or 'o' as normal text.
  static final _bulletRe = RegExp(r'^[•\-*▪·◦○●]\s+');

  /// Ordered: digits or letters + '.' / ')' + whitespace.
  static final _orderedRe = RegExp(r'^(\d+[.)]\s+|[a-zA-Z][.)]\s+)');
  static final _indexRe = RegExp(r'^\d+');

  /// Convert paragraphs (list of lines) → markdown blocks.
  ///
  /// [TableDetector] called first to tag table groups
  /// (lines with consistent gaps); non-table groups processed per paragraph.
  List<Block> classify(List<List<Line>> paragraphs) {
    final profile = _profile ?? _defaultProfile();
    final tagged = _tableDetector.tag(paragraphs, profile);

    final blocks = <Block>[];
    for (final (group, isTable) in tagged) {
      if (isTable) {
        _classifyTable(group, blocks);
      } else {
        for (final para in group) {
          _classifyParagraph(para, blocks);
        }
      }
    }
    return blocks;
  }

  /// Fallback profile if classifier constructed without profile:
  /// no heading bands or margin geometry.
  DocProfile _defaultProfile() => DocProfile(
        bodyFontSize: bodyFontSize,
        headingBands: const [],
        totalPages: 0,
        emptyPages: 0,
      );

  /// Classify table group → [BlockType.tableHeader] (first line)
  /// + [BlockType.tableRow] (subsequent lines), cells extracted via
  /// median split positions [TableDetector.computeMedianSplitXs].
  void _classifyTable(List<List<Line>> tableParas, List<Block> blocks) {
    if (tableParas.isEmpty) return;
    final splitXs = _tableDetector.computeMedianSplitXs(tableParas);
    final alignments = _tableDetector.computeAlignments(tableParas, splitXs);

    for (var i = 0; i < tableParas.length; i++) {
      final line = tableParas[i].first;
      final cells = _tableDetector.extractCells(line, splitXs);
      final type = i == 0 ? BlockType.tableHeader : BlockType.tableRow;
      blocks.add(Block(
        type: type,
        lines: [cells.join(' | ')],
        cells: cells,
        alignments: alignments.isEmpty ? null : alignments,
      ));
    }
  }

  /// Maximum nested list depth (0..3 = 4 levels, common in markdown).
  static const int maxListDepth = 3;

  /// Calculate nested list depth from xLeft.
  /// Depth = floor((xLeft - bodyLeftMargin) / step),
  /// step = 1.5 * bodyFontSize, clamped to [0, maxListDepth].
  int _listDepth(Line line) {
    final p = _profile;
    if (p == null || p.bodyLeftMargin <= 0) return 0;
    final xLeft = line.spans.isNotEmpty ? line.spans.first.xLeft : 0;
    final step = 1.5 * p.bodyFontSize;
    if (step <= 0) return 0;
    final depth = ((xLeft - p.bodyLeftMargin) / step).floor();
    return depth.clamp(0, maxListDepth);
  }

  /// Classify a single non-table paragraph: heading, list, or paragraph.
  void _classifyParagraph(List<Line> para, List<Block> blocks) {
    final firstLine = para.first;
    final text = para.map((l) => l.text.trim()).join(' ').trim();

    if (_isHeading(firstLine)) {
      blocks.add(Block(
        type: BlockType.heading,
        lines: [text],
        headingLevel: _headingLevel(firstLine),
      ));
      return;
    }

    final t = para.first.text.trim();
    final isOrdered = _orderedRe.hasMatch(t);
    if (_isBullet(t) || isOrdered) {
      _classifyList(para, blocks, ordered: isOrdered);
      return;
    }

    blocks.add(Block(type: BlockType.paragraph, lines: [text]));
  }

  /// A single paragraph containing list items: each bulleted/numbered line becomes
  /// a separate list item; continuation lines (without marker) append to item.
  void _classifyList(List<Line> para, List<Block> blocks, {bool ordered = false}) {
    for (final line in para) {
      final t = line.text.trim();
      final isOrderedLine = _orderedRe.hasMatch(t);
      final isMarkerLine = ordered ? isOrderedLine : _isBullet(t);

      if (isMarkerLine) {
        blocks.add(_buildListItem(line, t, ordered));
      } else if (blocks.isNotEmpty && blocks.last.type != BlockType.paragraph) {
        blocks[blocks.length - 1] = _appendLine(blocks.last, t);
      } else {
        blocks.add(Block(type: BlockType.paragraph, lines: [t]));
      }
    }
  }

  /// New list item from a single line with marker (bullet/ordered).
  Block _buildListItem(Line line, String text, bool ordered) => Block(
        type: ordered ? BlockType.orderedListItem : BlockType.unorderedListItem,
        lines: [ordered ? _stripOrdered(text) : _stripBullet(text)],
        listIndex: ordered ? _parseIndex(text) : null,
        listDepth: _listDepth(line),
      );

  /// Append continuation line (without marker) to previous list item,
  /// preserving item metadata.
  Block _appendLine(Block block, String text) => Block(
        type: block.type,
        lines: [...block.lines, text],
        listIndex: block.listIndex,
        listDepth: block.listDepth,
      );

  bool _isHeading(Line line) {
    if (bodyFontSize <= 0) return false;
    if (_profile?.bandForSize(line.fontSize) != null) return true;
    return line.fontSize >= bodyFontSize * config.headingFontFactor;
  }

  /// Heading level: profile band preferred; fallback factor → level 1.
  int _headingLevel(Line line) {
    final band = _profile?.bandForSize(line.fontSize);
    if (band != null) return band.headingLevel;
    return 1;
  }

  /// Public wrapper for paragraph joiner.
  bool isHeading(Line line) => _isHeading(line);

  bool _isBullet(String text) {
    if (text.isEmpty) return false;
    return _bulletRe.hasMatch(text);
  }

  /// Strip bullet + whitespace ('• item' → 'item').
  String _stripBullet(String text) => text.substring(1).trim();

  /// Strip ordered marker ('1. First' / 'a) Alpha' → 'First' / 'Alpha').
  String _stripOrdered(String text) => text.replaceFirst(_orderedRe, '').trim();

  /// Item index number ('1.' / '1)' → 1); null for letter markers.
  int? _parseIndex(String text) =>
      int.tryParse(_indexRe.firstMatch(text)?.group(0) ?? '');
}
