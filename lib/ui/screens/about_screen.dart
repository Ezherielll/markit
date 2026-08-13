import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';
import 'package:url_launcher/url_launcher.dart';

/// About screen — explanation of MarkIt for end users (non-technical).
/// Opened from info icon in header toolbar.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static const String _githubUrl = 'https://github.com/Ezherielll/MarkIt';

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final paper = isDark ? MarkitColors.paperDark : MarkitColors.paperLight;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return Scaffold(
      backgroundColor: paper,
      appBar: AppBar(
        backgroundColor: isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          tooltip: Strings.back,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text(
          Strings.aboutTitle,
          style: TextStyle(
            fontFamily: MarkitTypography.display,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(MarkitSpacing.xxl),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero — identity & core value.
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [primary, primary.withValues(alpha: 0.72)],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.description_rounded,
                        size: 24,
                        // onPrimary: white on the dark-blue gradient (light),
                        // dark ink on the light-blue gradient (dark) — plain
                        // Colors.white would vanish on dark-mode primary.
                        color: onPrimary,
                      ),
                    ),
                    const SizedBox(width: MarkitSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Strings.appTitle,
                            style: TextStyle(
                              fontFamily: MarkitTypography.display,
                              fontSize: 26,
                              height: 1.1,
                              fontWeight: FontWeight.w600,
                              color: ink,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            Strings.aboutHero,
                            style: TextStyle(
                              fontFamily: MarkitTypography.ui,
                              fontSize: 13,
                              color: inkMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MarkitSpacing.xl),
                Text(
                  Strings.aboutIntro,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: MarkitSpacing.xxl),

                // How it works.
                _SectionTitle(
                  icon: Icons.auto_stories_outlined,
                  title: Strings.aboutHowTitle,
                  subtitle: Strings.aboutHowSub,
                ),
                const SizedBox(height: MarkitSpacing.md),
                const _StepCard(
                  number: '1',
                  title: Strings.aboutStep1Title,
                  body: Strings.aboutStep1Sub,
                ),
                const SizedBox(height: MarkitSpacing.md),
                const _StepCard(
                  number: '2',
                  title: Strings.aboutStep2Title,
                  body: Strings.aboutStep2Sub,
                ),
                const SizedBox(height: MarkitSpacing.md),
                const _StepCard(
                  number: '3',
                  title: Strings.aboutStep3Title,
                  body: Strings.aboutStep3Sub,
                ),
                const SizedBox(height: MarkitSpacing.xxl),

                // Supported formats.
                _SectionTitle(
                  icon: Icons.folder_open_outlined,
                  title: Strings.aboutFormatsTitle,
                  subtitle: Strings.aboutFormatsList,
                ),
                const SizedBox(height: MarkitSpacing.md),
                _InfoCard(
                  icon: Icons.check_circle_outline,
                  title: Strings.aboutFormatsList,
                  body: Strings.aboutFormatsMore,
                ),
                const SizedBox(height: MarkitSpacing.xxl),

                // Privacy — key points.
                _SectionTitle(
                  icon: Icons.lock_outline,
                  title: Strings.aboutPrivacyTitle,
                ),
                const SizedBox(height: MarkitSpacing.md),
                const _InfoCard(
                  icon: Icons.offline_pin_outlined,
                  title: Strings.aboutPrivacyTitle,
                  body: Strings.aboutPrivacySub,
                  highlight: true,
                ),
                const SizedBox(height: MarkitSpacing.xxl),

                // FAQ.
                _SectionTitle(
                  icon: Icons.help_outline,
                  title: Strings.aboutFaqTitle,
                ),
                const SizedBox(height: MarkitSpacing.md),
                const _FaqCard(
                  q: Strings.aboutFaq1Q,
                  a: Strings.aboutFaq1A,
                ),
                const SizedBox(height: MarkitSpacing.sm),
                const _FaqCard(
                  q: Strings.aboutFaq2Q,
                  a: Strings.aboutFaq2A,
                ),
                const SizedBox(height: MarkitSpacing.sm),
                const _FaqCard(
                  q: Strings.aboutFaq3Q,
                  a: Strings.aboutFaq3A,
                ),
                const SizedBox(height: MarkitSpacing.sm),
                const _FaqCard(
                  q: Strings.aboutFaq4Q,
                  a: Strings.aboutFaq4A,
                ),
                const SizedBox(height: MarkitSpacing.xxl),

                // Footer.
                Center(
                  child: Column(
                    children: [
                      Text(
                        Strings.aboutFooter,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: MarkitTypography.display,
                          fontSize: 15,
                          fontStyle: FontStyle.italic,
                          color: inkMuted,
                        ),
                      ),
                      const SizedBox(height: MarkitSpacing.md),
                      OutlinedButton.icon(
                        onPressed: () async {
                          final ok = await launchUrl(
                            Uri.parse(_githubUrl),
                            mode: LaunchMode.externalApplication,
                          );
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Could not open the link.'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.code, size: 16),
                        label: const Text(Strings.aboutViewSource),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: MarkitSpacing.xl),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Section title: icon + title + optional subtitle.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.title, this.subtitle});

  final IconData icon;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 17, color: primary),
        ),
        const SizedBox(width: MarkitSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontFamily: MarkitTypography.display,
                  fontSize: 19,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: ink,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(fontSize: 12.5, color: inkMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Numbered step card (1/2/3).
class _StepCard extends StatelessWidget {
  const _StepCard({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(MarkitSpacing.lg),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: TextStyle(
                fontFamily: MarkitTypography.ui,
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: primary,
              ),
            ),
          ),
          const SizedBox(width: MarkitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: MarkitTypography.ui,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// General info card (formats / privacy).
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
    this.highlight = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.all(MarkitSpacing.lg),
      decoration: BoxDecoration(
        color: highlight
            ? primary.withValues(alpha: isDark ? 0.1 : 0.05)
            : surface,
        borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
        border: Border.all(
          color: highlight ? primary.withValues(alpha: 0.35) : hairline,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: primary),
          const SizedBox(width: MarkitSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontFamily: MarkitTypography.mono,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  body,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.55,
                    color: inkMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// FAQ card: question (bold) + answer.
class _FaqCard extends StatelessWidget {
  const _FaqCard({required this.q, required this.a});

  final String q;
  final String a;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    final ink = isDark ? MarkitColors.inkDark : MarkitColors.inkLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(MarkitSpacing.lg),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(MarkitSpacing.radiusCard),
        border: Border.all(color: hairline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            q,
            style: TextStyle(
              fontFamily: MarkitTypography.ui,
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            a,
            style: TextStyle(
              fontSize: 13,
              height: 1.55,
              color: inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}
