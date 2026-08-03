import '../models/layout.dart';
import 'doc_stats.dart';

/// Stage 4: klasifikasi struktur (FR-05 heading 2-tier, FR-06 list).
///
/// Heading: fontSize baris >= body * [PipelineConfig.headingFontFactor].
/// List: teks paragraf diawali karakter bullet (•, -, *, o, ▪).
class StructureClassifier {
  StructureClassifier({
    required this.bodyFontSize,
    this.config = const PipelineConfig(),
  });

  final double bodyFontSize;
  final PipelineConfig config;

  static const _bulletChars = {'•', '-', '*', 'o', '▪', '·', '◦'};

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
          headingLevel: 1,
        ));
        continue;
      }

      if (_isBullet(para.first.text.trim())) {
        _classifyList(para, blocks);
        continue;
      }

      blocks.add(Block(type: BlockType.paragraph, lines: [text]));
    }
    return blocks;
  }

  /// Satu paragraf dimulai bullet: tiap baris bullet jadi item list terpisah;
  /// baris lanjutan (tanpa bullet) menyambung ke item sebelumnya.
  void _classifyList(List<Line> para, List<Block> blocks) {
    for (final line in para) {
      final t = line.text.trim();
      if (_isBullet(t)) {
        blocks.add(Block(type: BlockType.listItem, lines: [t.substring(1).trim()]));
      } else if (blocks.isNotEmpty && blocks.last.type == BlockType.listItem) {
        blocks[blocks.length - 1] = Block(
          type: BlockType.listItem,
          lines: [...blocks.last.lines, t],
        );
      } else {
        blocks.add(Block(type: BlockType.paragraph, lines: [t]));
      }
    }
  }

  bool _isHeading(Line line) {
    if (bodyFontSize <= 0) return false;
    return line.fontSize >= bodyFontSize * config.headingFontFactor;
  }

  /// Public wrapper untuk paragraph joiner.
  bool isHeading(Line line) => _isHeading(line);

  bool _isBullet(String text) {
    if (text.isEmpty) return false;
    return _bulletChars.contains(text[0]);
  }
}
