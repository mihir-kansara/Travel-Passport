import 'package:flutter/material.dart';
import 'package:flutter_application_trial/ui/app_colors.dart';

class AppTextStyles {
  static TextTheme textTheme(TextTheme base) {
    const fontFamily = 'Plus Jakarta Sans';
    final themed = base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        fontFamily: fontFamily,
      ),
      titleLarge: base.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        fontFamily: fontFamily,
      ),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        fontFamily: fontFamily,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        fontFamily: fontFamily,
      ),
      bodyLarge: base.bodyLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        fontFamily: fontFamily,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        fontFamily: fontFamily,
      ),
      bodySmall: base.bodySmall?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        fontFamily: fontFamily,
      ),
      labelLarge: base.labelLarge?.copyWith(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        fontFamily: fontFamily,
      ),
      labelMedium: base.labelMedium?.copyWith(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        fontFamily: fontFamily,
      ),
      labelSmall: base.labelSmall?.copyWith(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.4,
        fontFamily: fontFamily,
      ),
    );
    return themed.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );
  }
}
