import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';

/// Header minimal: wordmark serif + aksi reset.
class AppHeader extends StatelessWidget {
  const AppHeader({super.key, required this.onReset, this.resetEnabled = true});

  final VoidCallback onReset;
  final bool resetEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? PdflowColors.inkDark : PdflowColors.inkLight;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: PdflowSpacing.xl,
        vertical: PdflowSpacing.lg,
      ),
      child: Row(
        children: [
          Icon(
            Icons.description_outlined,
            size: 22,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: PdflowSpacing.sm),
          Text(
            Strings.appTitle,
            style: TextStyle(
              fontFamily: PdflowTypography.display,
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          const Spacer(),
          IconButton(
            onPressed: resetEnabled ? onReset : null,
            icon: const Icon(Icons.restart_alt),
            tooltip: Strings.reset,
          ),
        ],
      ),
    );
  }
}
