import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:markit/core/format_catalog.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/models/pdf_input.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';
import 'package:markit/ui/theme/typography.dart';
import 'package:super_drag_and_drop/super_drag_and_drop.dart';

/// Open file picker dialog (multi-select, all formats recognized by MarkIt —
/// all 8 format families are convertible; legacy OLE2 extensions stay
/// detected-but-unsupported and show a clear "not supported yet" message,
/// not silent failure).
/// Desktop: PdfInput contains path; Web: contains bytes (no filesystem).
Future<List<PdfInput>> pickPdfFiles() async {
  final typeGroup = XTypeGroup(
    label: Strings.pickFileFilterName,
    extensions: kDetectableExtensions,
  );
  final files = await openFiles(acceptedTypeGroups: [typeGroup]);
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

/// Read file header (first 64 KB) — sufficient for magic bytes + ZIP entry
/// names without loading entire file.
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

/// Drop zone — accepts multiple PDF/document files via drag & drop (desktop) or
/// "Choose files" button.
///
/// [compact]: compact version for sidebar (no large sheet stack/hero).
class DropZone extends StatefulWidget {
  const DropZone({
    super.key,
    required this.onFilesPicked,
    this.compact = false,
  });

  /// Called with list of selected/dropped [PdfInput] files.
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
      final result = await _handleDropItem(item);
      if (result.input != null) inputs.add(result.input!);
      sawUrl = sawUrl || result.sawUrl;
      sawUnreadable = sawUnreadable || result.sawUnreadable;
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
      // Web: dropped file does not provide readable bytes —
      // direct user to picker button.
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

  /// Read single drop item: file (desktop) or constraint flags (web).
  ///
  /// - fileUri (desktop): real path → [PdfInput] ready for conversion.
  /// - fileUri (web): browser placeholder (no filesystem) → unreadable.
  /// - plainText (web): uri-list → classified per line (URL/unreadable).
  Future<({PdfInput? input, bool sawUrl, bool sawUnreadable})>
      _handleDropItem(DropItem item) async {
    final reader = item.dataReader;
    if (reader == null) return (input: null, sawUrl: false, sawUnreadable: false);

    if (reader.canProvide(Formats.fileUri)) {
      final completer = Completer<Uri?>();
      reader.getValue<Uri>(Formats.fileUri, (uri) {
        completer.complete(uri);
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      });
      final uri = await completer.future;
      if (uri == null) return (input: null, sawUrl: false, sawUnreadable: false);
      if (kIsWeb) {
        // Web: fileUri cannot be read (no filesystem) — path provided
        // by browser is a placeholder. Direct to picker.
        return (input: null, sawUrl: false, sawUnreadable: true);
      }
      final path = uri.toFilePath();
      final name = path.split(RegExp(r'[\\/]')).last;
      final header = await _readHeader(path);
      return (
        input: PdfInput(
          name: name,
          path: path,
          format: detectFormat(name, header),
        ),
        sawUrl: false,
        sawUnreadable: false,
      );
    }

    if (kIsWeb && reader.canProvide(Formats.plainText)) {
      // Web: browser provides File object — try via uri-list text.
      final completer = Completer<String?>();
      reader.getValue<String>(Formats.plainText, (text) {
        completer.complete(text);
      }, onError: (_) {
        if (!completer.isCompleted) completer.complete(null);
      });
      final text = await completer.future;
      final (:sawUrl, :sawUnreadable) =
          _classifyDropLines((text ?? '').split('\n'));
      return (input: null, sawUrl: sawUrl, sawUnreadable: sawUnreadable);
    }

    return (input: null, sawUrl: false, sawUnreadable: false);
  }

  /// Classify web drop uri-list lines: URL (requires network —
  /// violates offline policy) vs unreadable placeholder (direct to picker).
  static ({bool sawUrl, bool sawUnreadable}) _classifyDropLines(List<String> lines) {
    var sawUrl = false;
    var sawUnreadable = false;
    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (isUrlName(trimmed)) {
        sawUrl = true;
      } else {
        sawUnreadable = true;
      }
    }
    return (sawUrl: sawUrl, sawUnreadable: sawUnreadable);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hairline = isDark ? MarkitColors.hairlineDark : MarkitColors.hairlineLight;
    final surface = isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;
    final inkMuted = isDark ? MarkitColors.inkMutedDark : MarkitColors.inkMutedLight;

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
          borderRadius: BorderRadius.circular(MarkitSpacing.radiusDropzone),
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
          horizontal: widget.compact ? MarkitSpacing.lg : MarkitSpacing.xxxl,
          vertical: widget.compact ? MarkitSpacing.xl : MarkitSpacing.xxxl * 1.4,
        ),
        child: widget.compact
            ? _compactContent(inkMuted)
            : _fullContent(inkMuted, isDark),
      ),
    );
  }

  /// Compact version (sidebar): icon + short instructions + button.
  Widget _compactContent(Color inkMuted) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          _dragActive ? Icons.file_download_done : Icons.upload_file_outlined,
          size: 30,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: MarkitSpacing.md),
        Text(
          _dragActive ? Strings.dropHere : Strings.dropCompact,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: MarkitTypography.ui,
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
        const SizedBox(height: MarkitSpacing.lg),
        FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.folder_open, size: 17),
          label: const Text(Strings.pickFile),
        ),
      ],
    );
  }

  /// Full version (hero empty state): sheet stack + headline + features.
  Widget _fullContent(Color inkMuted, bool isDark) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const _SheetStack(),
        const SizedBox(height: MarkitSpacing.xl),
        Icon(
          Icons.picture_as_pdf_outlined,
          size: 40,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(height: MarkitSpacing.lg),
        Text(
          _dragActive ? Strings.dropHere : Strings.heroHeadline,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: MarkitTypography.display,
            fontSize: 30,
            height: 1.15,
            fontWeight: FontWeight.w600,
            fontVariations: const [FontVariation('opsz', 36)],
            color: isDark ? MarkitColors.inkDark : MarkitColors.inkLight,
          ),
        ),
        const SizedBox(height: MarkitSpacing.md),
        Text(
          Strings.heroSub,
          textAlign: TextAlign.center,
          style: TextStyle(color: inkMuted),
        ),
        const SizedBox(height: MarkitSpacing.xl),
        FilledButton.icon(
          onPressed: _pick,
          icon: const Icon(Icons.folder_open, size: 18),
          label: const Text(Strings.pickFile),
        ),
        const SizedBox(height: MarkitSpacing.md),
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

/// Sheet stack motif — signature empty state.
class _SheetStack extends StatelessWidget {
  const _SheetStack();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final edge = isDark ? MarkitColors.sheetEdgeDark : MarkitColors.sheetEdgeLight;
    final surface = isDark ? MarkitColors.surfaceDark : MarkitColors.surfaceLight;

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
