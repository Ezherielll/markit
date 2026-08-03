import 'package:flutter/material.dart';

/// Palet "Document Studio" — kertas, tinta, tinta pulpen, stempel.
/// Grounded pada subjek (PDF → Markdown): hangat, desaturated, editorial.
abstract final class PdflowColors {
  // ── Light ───────────────────────────────────────────────
  static const paperLight = Color(0xFFF6F4EF);
  static const surfaceLight = Color(0xFFFDFCFA);
  static const surfaceRaisedLight = Color(0xFFFFFFFF);
  static const inkLight = Color(0xFF211F1C);
  static const inkMutedLight = Color(0xFF6E6A63);
  static const penBlueLight = Color(0xFF274C8A);
  static const penBlueSoftLight = Color(0xFFE4EAF4);
  static const stampGreenLight = Color(0xFF3D6B4F);
  static const stampRedLight = Color(0xFF8A3B32);
  static const hairlineLight = Color(0xFFE2DED6);
  static const sheetEdgeLight = Color(0xFFE9E4DA);

  // ── Dark ────────────────────────────────────────────────
  static const paperDark = Color(0xFF161513);
  static const surfaceDark = Color(0xFF201E1C);
  static const surfaceRaisedDark = Color(0xFF2A2724);
  static const inkDark = Color(0xFFEDE8DF);
  static const inkMutedDark = Color(0xFFA49E94);
  static const penBlueDark = Color(0xFF8FB2E8);
  static const penBlueSoftDark = Color(0xFF2A3A55);
  static const stampGreenDark = Color(0xFF7FB590);
  static const stampRedDark = Color(0xFFD98E82);
  static const hairlineDark = Color(0xFF3A3733);
  static const sheetEdgeDark = Color(0xFF302D29);
}
