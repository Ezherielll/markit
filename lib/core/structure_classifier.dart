import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage 4: klasifikasi struktur (FR-05 heading 2-tier, FR-06 list).
///
/// Fase A: heading multi-level berbasis [DocProfile.headingBands]
/// (band ukuran font → level H1..H4); fallback legacy faktor heading
/// bila profil tidak tersedia. List detection pattern-based:
/// bullet wajib diikuti whitespace ('o' bukan bullet), ordered list
/// `1.` / `1)` / `a.` / `a)` didukung.
class StructureClassifier {
  StructureClassifier({
    required this.bodyFontSize,
    this.config = const PipelineConfig(),
    this.profile,
  });

  /// Factory utama (Fase A): profil pass 1 dengan pita heading.
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

  /// Profil pass 1 (opsional, backward compat) untuk multi-band heading.
  final DocProfile? profile;

  /// Bullet wajib diikuti whitespace — menghindari false positive
  /// seperti '-3°C' atau 'o' sebagai huruf biasa (design §4.5).
  static final _bulletRe = RegExp(r'^[•\-*▪·◦○●]\s+');

  /// Ordered: angka atau huruf + '.' / ')' + whitespace (design §4.5).
  static final _orderedRe = RegExp(r'^(\d+[.)]\s+|[a-zA-Z][.)]\s+)');
  static final _indexRe = RegExp(r'^\d+');

  /// Konversi paragraf (list of lines) → blok markdown.
  List<Block> classify(List<List<Line>> paragraphs) {
    final blocks = <Block>[];
    for (final para in paragraphs) {
      final firstLine = para.first;
      final text = para.map((l) => l.text.trim()).join(' ').trim();

      if (_isHeading(firstLine)) {
        blocks.add(Block(
          type: BlockType.heading,
          lines: [text],
          headingLevel: _headingLevel(firstLine),
        ));
        continue;
      }

      final t = para.first.text.trim();
      final isOrdered = _orderedRe.hasMatch(t);
      if (_isBullet(t) || isOrdered) {
        _classifyList(para, blocks, ordered: isOrdered);
        continue;
      }

      blocks.add(Block(type: BlockType.paragraph, lines: [text]));
    }
    return blocks;
  }

  /// Satu paragraf berisi item list: tiap baris ber-bullet/bernomor jadi
  /// item list terpisah; baris lanjutan (tanpa marker) menyambung ke item.
  void _classifyList(List<Line> para, List<Block> blocks, {bool ordered = false}) {
    for (final line in para) {
      final t = line.text.trim();
      final isOrderedLine = _orderedRe.hasMatch(t);
      final isMarkerLine = ordered ? isOrderedLine : _isBullet(t);

      if (isMarkerLine) {
        blocks.add(Block(
          type: ordered ? BlockType.orderedListItem : BlockType.unorderedListItem,
          lines: [ordered ? _stripOrdered(t) : _stripBullet(t)],
          listIndex: ordered ? _parseIndex(t) : null,
        ));
      } else if (blocks.isNotEmpty && blocks.last.type != BlockType.paragraph) {
        blocks[blocks.length - 1] = Block(
          type: blocks.last.type,
          lines: [...blocks.last.lines, t],
          listIndex: blocks.last.listIndex,
        );
      } else {
        blocks.add(Block(type: BlockType.paragraph, lines: [t]));
      }
    }
  }

  bool _isHeading(Line line) {
    if (bodyFontSize <= 0) return false;
    if (profile?.bandForSize(line.fontSize) != null) return true;
    return line.fontSize >= bodyFontSize * config.headingFontFactor;
  }

  /// Level heading: band profil lebih diutamakan; fallback faktor → level 1.
  int _headingLevel(Line line) {
    final band = profile?.bandForSize(line.fontSize);
    if (band != null) return band.headingLevel;
    return 1;
  }

  /// Public wrapper untuk paragraph joiner.
  bool isHeading(Line line) => _isHeading(line);

  bool _isBullet(String text) {
    if (text.isEmpty) return false;
    return _bulletRe.hasMatch(text);
  }

  /// Hapus bullet + whitespace ('• item' → 'item').
  String _stripBullet(String text) => text.substring(1).trim();

  /// Hapus marker ordered ('1. First' / 'a) Alpha' → 'First' / 'Alpha').
  String _stripOrdered(String text) => text.replaceFirst(_orderedRe, '').trim();

  /// Nomor item ('1.' / '1)' → 1); null untuk marker huruf.
  int? _parseIndex(String text) =>
      int.tryParse(_indexRe.firstMatch(text)?.group(0) ?? '');
}
