import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';

/// Kartu info file PDF terpilih: nama, ukuran, jumlah halaman, body font.
class FileCard extends StatefulWidget {
  const FileCard({super.key, required this.path, this.pageCount, this.bodyFontSize});

  final String path;
  final int? pageCount;
  final double? bodyFontSize;

  @override
  State<FileCard> createState() => _FileCardState();
}

class _FileCardState extends State<FileCard> {
  int? _sizeBytes;

  @override
  void initState() {
    super.initState();
    _loadSize();
  }

  Future<void> _loadSize() async {
    final f = File(widget.path);
    if (!await f.exists()) return;
    final size = await f.length();
    if (mounted) setState(() => _sizeBytes = size);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;

    final name = widget.path.split(Platform.pathSeparator).last;
    final size = _sizeBytes == null
        ? null
        : '${(_sizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB';

    return Container(
      padding: const EdgeInsets.all(PdflowSpacing.lg),
      decoration: BoxDecoration(
        color: isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight,
        borderRadius: BorderRadius.circular(PdflowSpacing.radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.picture_as_pdf_outlined,
              size: 30,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: PdflowSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: PdflowTypography.mono,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: ink,
                    )),
                const SizedBox(height: 4),
                Text(
                  [
                    ?size,
                    if (widget.pageCount != null)
                      '${widget.pageCount} ${Strings.pagesLabel}',
                    if (widget.bodyFontSize != null)
                      '${Strings.statsBodyFont} ${widget.bodyFontSize!.toStringAsFixed(1)}',
                  ].join('  ·  '),
                  style: TextStyle(fontSize: 12.5, color: inkMuted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
