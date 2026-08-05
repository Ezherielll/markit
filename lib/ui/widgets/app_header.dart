import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/theme/theme_controller.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';

/// Header minimal: wordmark serif + toggle tema + aksi reset.
class AppHeader extends StatelessWidget {
  const AppHeader({
    super.key,
    required this.onReset,
    required this.themeController,
    this.resetEnabled = true,
  });

  final VoidCallback onReset;
  final ThemeController themeController;
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
          ListenableBuilder(
            listenable: themeController,
            builder: (context, _) {
              final mode = themeController.mode;
              final icon = switch (mode) {
                ThemeMode.light => Icons.light_mode_outlined,
                ThemeMode.dark => Icons.dark_mode_outlined,
                ThemeMode.system => Icons.brightness_auto_outlined,
              };
              final label = switch (mode) {
                ThemeMode.light => Strings.themeLight,
                ThemeMode.dark => Strings.themeDark,
                ThemeMode.system => Strings.themeSystem,
              };
              return IconButton(
                onPressed: themeController.cycle,
                icon: Icon(icon),
                tooltip: '${Strings.themeToggle} ($label)',
              );
            },
          ),
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
