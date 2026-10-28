/// Typography — consistent text styles across the app.
library app_typography;

import 'package:flutter/material.dart';
import 'app_colors.dart';

abstract final class AppTypography {
  static const _base = TextStyle(
    fontFamily: 'sans-serif',
    color: AppColors.textPrimary,
    letterSpacing: 0.2,
  );

  static final displayLarge = _base.copyWith(fontSize: 28, fontWeight: FontWeight.w700);
  static final displayMedium = _base.copyWith(fontSize: 22, fontWeight: FontWeight.w600);
  static final titleLarge = _base.copyWith(fontSize: 18, fontWeight: FontWeight.w600);
  static final titleMedium = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w500);
  static final bodyLarge = _base.copyWith(fontSize: 15, fontWeight: FontWeight.w400);
  static final bodyMedium = _base.copyWith(fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.textSecondary);
  static final labelSmall = _base.copyWith(fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.6);
  static final mono = _base.copyWith(fontFamily: 'monospace', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.primary);
}
