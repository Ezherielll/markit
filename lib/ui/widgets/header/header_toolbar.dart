import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/theme/theme_controller.dart';
import 'package:markit/ui/theme/palette.dart';

/// Toolbar aksi kanan header — grup rounded container yang kohesif.
/// Skalabel: tambah aksi (search, notifications, profile, dll) di sini.
class HeaderToolbar extends StatelessWidget {
  const HeaderToolbar({
    super.key,
    required this.themeController,
    required this.onReset,
    this.resetEnabled = true,
  });

  final ThemeController themeController;
  final VoidCallback onReset;
  final bool resetEnabled;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? PdflowColors.surfaceRaisedDark : PdflowColors.surfaceRaisedLight;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    final hover = Theme.of(context).colorScheme.primary.withValues(alpha: 0.08);

    final iconStyle = IconButton.styleFrom(
      visualDensity: VisualDensity.compact,
      minimumSize: const Size(34, 34),
      hoverColor: hover,
      splashFactory: InkRipple.splashFactory,
    );

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Appearance toggle (light / dark / system).
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
                icon: Icon(icon, size: 19),
                tooltip: '${Strings.themeToggle} ($label)',
                style: iconStyle,
              );
            },
          ),
          // Settings — placeholder (fitur belum ada).
          IconButton(
            onPressed: null,
            icon: const Icon(Icons.settings_outlined, size: 19),
            tooltip: Strings.settingsTooltip,
            style: iconStyle,
          ),
          Container(
            width: 1,
            height: 20,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            color: hairline,
          ),
          IconButton(
            onPressed: resetEnabled ? onReset : null,
            icon: const Icon(Icons.restart_alt, size: 19),
            tooltip: Strings.reset,
            style: iconStyle,
          ),
        ],
      ),
    );
  }
}
