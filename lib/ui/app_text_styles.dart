import 'package:flutter/material.dart';
import 'package:flutter_application_trial/ui/app_colors.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTextStyles {
  static TextTheme textTheme(TextTheme base) {
    final themed = _withSizing(base);
    return themed.apply(
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    );
  }

  static TextTheme _withSizing(TextTheme base) {
    try {
      return GoogleFonts.plusJakartaSansTextTheme(base).copyWith(
        headlineSmall: base.headlineSmall?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: base.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.titleSmall?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.bodyLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodyMedium: base.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodySmall: base.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        labelLarge: base.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: base.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        labelSmall: base.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      );
    } catch (_) {
      return base.copyWith(
        headlineSmall: base.headlineSmall?.copyWith(
          fontSize: 26,
          fontWeight: FontWeight.w800,
        ),
        titleLarge: base.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
        titleMedium: base.titleMedium?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
        ),
        titleSmall: base.titleSmall?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w700,
        ),
        bodyLarge: base.bodyLarge?.copyWith(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodyMedium: base.bodyMedium?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        bodySmall: base.bodySmall?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          height: 1.4,
        ),
        labelLarge: base.labelLarge?.copyWith(
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        labelMedium: base.labelMedium?.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        labelSmall: base.labelSmall?.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        ),
      );
    }
  }
}
