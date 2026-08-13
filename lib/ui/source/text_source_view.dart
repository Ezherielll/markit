import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/ui/source/source_loader.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';

/// Raw text view for source files: monospace, no-wrap, selection enabled.
class TextSourceView extends StatelessWidget {
  const TextSourceView({super.key, required this.data});

  final SourceText data;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final inkMuted = isDark
        ? MarkitColors.inkMutedDark
        : MarkitColors.inkMutedLight;
    final controller = ScrollController();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.truncated)
          Padding(
            padding: const EdgeInsets.only(bottom: MarkitSpacing.md),
            child: Text(
              Strings.sourceTruncated,
              style: TextStyle(
                fontSize: 12,
                fontStyle: FontStyle.italic,
                color: inkMuted,
              ),
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: controller,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: controller,
              scrollDirection: Axis.horizontal,
              child: SelectionArea(
                child: Text(
                  data.content,
                  softWrap: false,
                  style: const TextStyle(
                    fontFamily: MarkitTypography.mono,
                    fontSize: 12.5,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
