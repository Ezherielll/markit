import 'package:flutter/material.dart';
import 'package:markit/i18n/strings.dart';
import 'package:markit/isolate/conversion_controller.dart';
import 'package:markit/ui/theme/palette.dart';
import 'package:markit/ui/theme/spacing.dart';

/// Panel error untuk satu job gagal — pesan LENGKAP (wrap), tidak
/// terpotong ellipsis. Judul dipetakan dari errorType; body = errorMessage
/// asli (atau fallback judul). Tombol "Show full error" membuka dialog
/// dengan SelectableText penuh.
class JobErrorView extends StatelessWidget {
  const JobErrorView({super.key, required this.job});

  final QueuedFile job;

  /// Judul ramah per errorType; fallback errorGeneric.
  String get _title {
    return switch (job.errorType) {
      'encrypted' => Strings.errorEncrypted,
      'noText' => Strings.errorNoText,
      'corrupt' => Strings.errorCorrupt,
      'unsupported' => Strings.errorUnsupported,
      _ => Strings.errorGeneric.replaceFirst('%s', job.errorType ?? ''),
    };
  }

  /// Body penuh: pesan asli dari executor bila ada, else judul mapping.
  String get _body {
    final message = job.errorMessage;
    if (message != null && message.isNotEmpty) return message;
    return _title;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final red = isDark ? PdflowColors.stampRedDark : PdflowColors.stampRedLight;
    final message = job.errorMessage;
    final hasMessage = message != null && message.isNotEmpty;
    // Pesan panjang (> ~3 baris kartu) → butuh tombol dialog.
    final showDialogButton = (message?.length ?? 0) > 90;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(PdflowSpacing.sm),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: red.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 16, color: red),
          const SizedBox(width: PdflowSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: red,
                    height: 1.35,
                  ),
                ),
                if (hasMessage) ...[
                  const SizedBox(height: 2),
                  // Pesan lengkap, wrap — TIDAK pakai ellipsis.
                  Text(
                    _body,
                    style: TextStyle(fontSize: 10.5, color: red, height: 1.35),
                  ),
                ],
                if (showDialogButton) ...[
                  const SizedBox(height: 2),
                  InkWell(
                    onTap: () => _showFullDialog(context),
                    child: Text(
                      Strings.showFullError,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: red,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showFullDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(job.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
        content: SingleChildScrollView(
          child: SelectableText(_body, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text(Strings.close),
          ),
        ],
      ),
    );
  }
}
