/// App color palette — single source of truth for all colors.
library app_colors;

import 'package:flutter/material.dart';

abstract final class AppColors {
  // ── Brand ─────────────────────────────────────────────────────────────────
  static const primary = Color(0xFF00E5CC);       // Electric teal
  static const primaryDark = Color(0xFF00B0A0);
  static const accent = Color(0xFF6C63FF);         // Soft violet

  // ── Backgrounds ──────────────────────────────────────────────────────────
  static const background = Color(0xFF0D1117);     // Deep navy-black
  static const surface = Color(0xFF161B22);        // Card surface
  static const surfaceVariant = Color(0xFF1F2937); // Elevated surface

  // ── Status ────────────────────────────────────────────────────────────────
  static const callGreen = Color(0xFF22C55E);
  static const callRed = Color(0xFFEF4444);
  static const wifiBlue = Color(0xFF3B82F6);
  static const btBlue = Color(0xFF1D4ED8);
  static const speaking = Color(0xFF00E5CC);

  // ── Text ──────────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF0F6FC);
  static const textSecondary = Color(0xFF8B949E);
  static const textMuted = Color(0xFF484F58);

  // ── Borders / Dividers ───────────────────────────────────────────────────
  static const border = Color(0xFF30363D);
}
