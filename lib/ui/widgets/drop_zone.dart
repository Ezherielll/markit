import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:pdflow/i18n/strings.dart';
import 'package:pdflow/ui/theme/palette.dart';
import 'package:pdflow/ui/theme/spacing.dart';
import 'package:pdflow/ui/theme/typography.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Buka dialog picker PDF (multi-select). Dipakai drop zone & tombol "Add files".
Future<List<String>> pickPdfFiles() async {
  const typeGroup = XTypeGroup(
    label: Strings.pickFileFilterName,
    extensions: ['pdf'],
  );
  final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
  return files.map((f) => f.path).toList();
}

/// Drop zone besar — menerima banyak file PDF via drag & drop (desktop) atau
/// tombol "Choose PDF files". Menampilkan visual "tumpukan lembaran".
class DropZone extends StatefulWidget {
  const DropZone({super.key, required this.onFilesPicked});

  /// Dipanggil dengan daftar path file PDF yang dipilih/di-drop.
  final ValueChanged<List<String>> onFilesPicked;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _dragActive = false;

  Future<void> _pick() async {
    final paths = await pickPdfFiles();
    if (paths.isEmpty) return;
    widget.onFilesPicked(paths);
  }

  Future<void> _onDrop(PerformDropEvent event) async {
    final paths = <String>[];
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;
      if (!reader.canProvide(Formats.fileUri)) continue;
      final completer = Completer<String?>();
      reader.getValue<Uri>(Formats.fileUri, (uri) {
        completer.complete(uri?.toFilePath());
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      });
      final path = await completer.future;
      if (path != null) paths.add(path);
    }
    if (paths.isNotEmpty && mounted) {
      widget.onFilesPicked(paths);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = isDark ? PdflowColors.hairlineDark : PdflowColors.hairlineLight;
    final surface = isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight;
    final inkMuted = isDark ? PdflowColors.inkMutedDark : PdflowColors.inkMutedLight;

    return DropRegion(
      formats: Formats.standardFormats,
      hitTestBehavior: HitTestBehavior.opaque,
      onDropOver: (event) => DropOperation.copy,
      onDropEnter: (_) => setState(() => _dragActive = true),
      onDropLeave: (_) => setState(() => _dragActive = false),
      onPerformDrop: _onDrop,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(PdflowSpacing.radiusDropzone),
          border: Border.all(
            color: _dragActive
                ? Theme.of(context).colorScheme.primary
                : hairline,
            width: _dragActive ? 2 : 1,
          ),
          boxShadow: _dragActive
              ? [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                    blurRadius: 24,
                    spreadRadius: 2,
                  ),
                ]
              : null,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: PdflowSpacing.xxxl,
          vertical: PdflowSpacing.xxxl * 1.4,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _SheetStack(),
            const SizedBox(height: PdflowSpacing.xl),
            Icon(
              Icons.picture_as_pdf_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: PdflowSpacing.lg),
            Text(
              _dragActive ? Strings.dropHere : Strings.heroHeadline,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: PdflowTypography.display,
                fontSize: 30,
                height: 1.15,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation('opsz', 36)],
                color: isDark ? PdflowColors.inkDark : PdflowColors.inkLight,
              ),
            ),
            const SizedBox(height: PdflowSpacing.md),
            Text(
              Strings.heroSub,
              textAlign: TextAlign.center,
              style: TextStyle(color: inkMuted),
            ),
            const SizedBox(height: PdflowSpacing.xl),
            FilledButton.icon(
              onPressed: _pick,
              icon: const Icon(Icons.folder_open, size: 18),
              label: const Text(Strings.pickFile),
            ),
            const SizedBox(height: PdflowSpacing.md),
            Text(
              Strings.dropSub,
              style: TextStyle(
                fontSize: 12,
                color: inkMuted,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Motif tumpukan lembaran (sheet stack) — signature empty state.
class _SheetStack extends StatelessWidget {
  const _SheetStack();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final edge = isDark ? PdflowColors.sheetEdgeDark : PdflowColors.sheetEdgeLight;
    final surface = isDark ? PdflowColors.surfaceDark : PdflowColors.surfaceLight;

    return SizedBox(
      width: 120,
      height: 56,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = 2; i >= 1; i--)
            Positioned(
              top: (2 - i) * 6.0,
              left: i * 14.0,
              right: i * 14.0,
              child: Container(
                height: 44,
                decoration: BoxDecoration(
                  color: edge,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: edge),
                ),
              ),
            ),
          Container(
            height: 44,
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: edge),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.08),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                Icons.notes,
                size: 26,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
