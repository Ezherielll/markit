import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markit/core/input_format.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Buka dialog picker file (multi-select, semua format didukung MarkIt).
/// Desktop: PdfInput berisi path; Web: berisi bytes (tanpa filesystem).
Future<List<PdfInput>> pickPdfFiles() async {
  const typeGroup = XTypeGroup(
    label: Strings.pickFileFilterName,
    extensions: [
      'pdf', 'txt', 'md', 'markdown', 'csv', 'json', 'xml', 'html', 'htm',
    ],
  );
  final files = await openFiles(acceptedTypeGroups: const [typeGroup]);
  final inputs = <PdfInput>[];
  for (final f in files) {
    if (kIsWeb) {
      final bytes = await f.readAsBytes();
      inputs.add(PdfInput(
        name: f.name,
        sizeBytes: await f.length(),
        bytes: bytes,
        format: detectFormat(f.name, bytes),
      ));
    } else {
      final header = await _readHeader(f.path);
      inputs.add(PdfInput(
        name: f.name,
        sizeBytes: await f.length(),
        path: f.path,
        format: detectFormat(f.name, header),
      ));
    }
  }
  return inputs;
}

/// Baca header file (64 KB pertama) — cukup untuk magic bytes + nama entry
/// ZIP (plan §4.2) tanpa memuat seluruh file.
Future<Uint8List> _readHeader(String path) async {
  try {
    final file = File(path);
    final raf = await file.open();
    try {
      final bytes = await raf.read(65536);
      return bytes;
    } finally {
      await raf.close();
    }
  } catch (_) {
    return Uint8List(0);
  }
}

/// Drop zone — menerima banyak file PDF via drag & drop (desktop) atau
/// tombol "Choose PDF files".
///
/// [compact]: versi ringkas untuk sidebar (tanpa sheet stack/hero besar).
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onFilesPicked,
    this.compact = false,
  });

  /// Dipanggil dengan daftar [PdfInput] file PDF yang dipilih/di-drop.
  final ValueChanged<List<PdfInput>> onFilesPicked;

  final bool compact;

  @override
  State<DropZone> createState() => _DropZoneState();
}

class _DropZoneState extends State<DropZone> {
  bool _dragActive = false;

  Future<void> _pick() async {
    final inputs = await pickPdfFiles();
    if (inputs.isEmpty) return;
    widget.onFilesPicked(inputs);
  }

  Future<void> _onDrop(PerformDropEvent event) async {
    final inputs = <PdfInput>[];
    var sawUrl = false;
    var sawUnreadable = false;
    for (final item in event.session.items) {
      final reader = item.dataReader;
      if (reader == null) continue;

      if (reader.canProvide(Formats.fileUri)) {
        final completer = Completer<Uri?>();
        reader.getValue<Uri>(Formats.fileUri, (uri) {
          completer.complete(uri);
        }, onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        });
        final uri = await completer.future;
        final path = uri?.toFilePath();
        if (path == null) continue;
        if (kIsWeb) {
          // Web: fileUri tidak bisa dibaca (tidak ada filesystem) — path yang
          // diberikan browser adalah placeholder. Arahkan ke picker.
          sawUnreadable = true;
          continue;
        }
        final name = path.split(RegExp(r'[\\/]')).last;
        final header = await _readHeader(path);
        inputs.add(
          PdfInput(
            name: name,
            path: path,
            format: detectFormat(name, header),
          ),
        );
      } else if (kIsWeb && reader.canProvide(Formats.plainText)) {
        // Web: browser memberi File object — coba lewat uri-list text.
        final completer = Completer<String?>();
        reader.getValue<String>(Formats.plainText, (text) {
          completer.complete(text);
        }, onError: (_) {
          if (!completer.isCompleted) completer.complete(null);
        });
        final text = await completer.future;
        for (final line in (text ?? '').split('\n')) {
          final trimmed = line.trim();
          if (trimmed.isEmpty) continue;
          if (isUrlName(trimmed)) {
            // URL butuh jaringan — melanggar NG3 (100% lokal).
            sawUrl = true;
            continue;
          }
          // Path uri-list browser adalah placeholder yang tak bisa dibaca di
          // web — jangan buat PdfInput palsu (itu menyebabkan error corrupt
          // saat konversi). Arahkan ke picker.
          sawUnreadable = true;
        }
      }
    }
    if (sawUrl && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(Strings.urlNotSupported),
        ),
      );
    }
    if (inputs.isNotEmpty && mounted) {
      widget.onFilesPicked(inputs);
    } else if (mounted) {
      // Web: file yang di-drop tidak menyediakan bytes yang bisa dibaca —
      // arahkan user ke tombol picker.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sawUnreadable
                ? Strings.dropNotSupported
                : Strings.dropNoFiles,
          ),
        ),
      );
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
        padding: EdgeInsets.symmetric(
          horizontal: widget.compact ? PdflowSpacing.lg : PdflowSpacing.xxxl,
          vertical: widget.compact ? PdflowSpacing.xl : PdflowSpacing.xxxl * 1.4,
        ),
        child: widget.compact
            ? _compactContent(inkMuted)
            : _fullContent(inkMuted, isDark),
      ),
    );
  }

  /// Versi ringkas (sidebar): ikon + instruksi singkat + tombol.
  Widget _compactContent(Color inkMuted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _dragActive ? Icons.file_download_done : Icons.upload_file_outlined,
          size: 30,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: PdflowSpacing.md),
        Text(
          _dragActive ? Strings.dropHere : Strings.dropCompact,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: PdflowTypography.ui,
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          Strings.dropCompactSub,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 11.5, color: inkMuted),
        ),
        const SizedBox(height: PdflowSpacing.lg),
        FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.folder_open, size: 17),
          label: const Text(Strings.pickFile),
        ),
      ],
    );
  }

  /// Versi penuh (hero empty state): sheet stack + headline + fitur.
  Widget _fullContent(Color inkMuted, bool isDark) {
    return Column(
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
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: isDark ? 0.28 : 0.10),
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
