import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Logo MarkIt `[M]` — tile rounded pen-blue, huruf "M" serif Fraunces,
/// diapit dua bracket vertikal. Geometri identik dengan icon platform
/// (tools/generate_icons.ps1), sehingga identitas konsisten di mana-mana.
class MarkItMark extends StatelessWidget {
  const MarkItMark({super.key, this.size = 36, this.showBrackets});

  /// Ukuran tile persegi (biasanya 36 di header, 64+ untuk hero).
  final double size;

  /// Bracket digambar bila null & ukuran cukup (>= 56) — di ukuran kecil
  /// bracket hanya noise, huruf M yang menjaga keterbacaan.
  final bool? showBrackets;

  @override
  Widget build(BuildContext context) {
    final showBars = showBrackets ?? size >= 56;
    return CustomPaint(
      size: Size.square(size),
      painter: _MarkItMarkPainter(showBrackets: showBars),
    );
  }
}

class _MarkItMarkPainter extends CustomPainter {
  _MarkItMarkPainter({required this.showBrackets});

  final bool showBrackets;

  static const _tile = Color(0xFF274C8A);
  static const _edge = Color(0xFF1F3F73);
  static const _glyph = Colors.white;
  static const _bracket = Color(0xFFF6F4EF);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(s * 0.09),
    );
    canvas.drawRRect(rrect, Paint()..color = _tile);
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.5, s * 0.004)
        ..color = _edge,
    );

    final boxW = s * 0.42;
    final boxH = s * 0.58;

    final painter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: TextStyle(
          fontFamily: 'Fraunces',
          color: _glyph,
          fontSize: s * 0.72,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final sc = math.min(boxW / painter.width, boxH / painter.height).clamp(0.0, 1.0);
    final mW = painter.width * sc;
    final mH = painter.height * sc;
    canvas.save();
    canvas.translate(s / 2 - mW / 2, s / 2 - mH / 2);
    canvas.scale(sc, sc);
    painter.paint(canvas, Offset.zero);
    canvas.restore();

    if (showBrackets && s >= 56) {
      final barW = s * 0.055;
      final barH = s * 0.60;
      final barY = (s - barH) / 2;
      final gap = s * 0.088;
      final paint = Paint()..color = _bracket.withValues(alpha: 0.95);
      for (final bx in [gap, s - gap - barW]) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(bx, barY, barW, barH),
            Radius.circular(barW / 2),
          ),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_MarkItMarkPainter oldDelegate) =>
      oldDelegate.showBrackets != showBrackets;
}
