import 'package:flutter/material.dart';
import 'package:flutter_application_trial/ui/app_colors.dart';
import 'package:flutter_application_trial/ui/app_radii.dart';
import 'package:flutter_application_trial/ui/app_spacing.dart';
import 'package:flutter_application_trial/ui/app_text_styles.dart';

export 'package:flutter_application_trial/ui/app_colors.dart';
export 'package:flutter_application_trial/ui/app_spacing.dart';
export 'package:flutter_application_trial/ui/app_radii.dart';
export 'package:flutter_application_trial/ui/app_text_styles.dart';

class AppShadows {
	static const soft = BoxShadow(
		color: Color(0x140F172A),
		blurRadius: 16,
		offset: Offset(0, 8),
	);
	static const elevated = BoxShadow(
		color: Color(0x240F172A),
		blurRadius: 24,
		offset: Offset(0, 12),
	);
}

class AppTheme {
	static ThemeData lightTheme() {
		final base = ThemeData.light();
		final inputBorder = OutlineInputBorder(
			borderRadius: BorderRadius.circular(AppRadii.md),
			borderSide: const BorderSide(color: AppColors.border),
		);
		return base.copyWith(
			colorScheme: const ColorScheme.light(
				primary: AppColors.primary,
				secondary: AppColors.secondary,
				surface: AppColors.surface,
				error: AppColors.danger,
			),
			scaffoldBackgroundColor: AppColors.background,
			textTheme: AppTextStyles.textTheme(base.textTheme),
			appBarTheme: const AppBarTheme(
				elevation: 0,
				backgroundColor: Colors.transparent,
				foregroundColor: AppColors.text,
				centerTitle: false,
			),
			iconTheme: const IconThemeData(color: AppColors.text),
			dividerTheme: const DividerThemeData(
				color: AppColors.border,
				thickness: 1,
				space: 1,
			),
			cardTheme: CardThemeData(
				elevation: 0,
				margin: const EdgeInsets.symmetric(
					horizontal: AppSpacing.lg,
					vertical: AppSpacing.sm,
				),
				color: AppColors.surface,
				shape: RoundedRectangleBorder(
					borderRadius: BorderRadius.circular(AppRadii.md),
				),
			),
			inputDecorationTheme: InputDecorationTheme(
				filled: true,
				fillColor: AppColors.surface,
				contentPadding: const EdgeInsets.symmetric(
					horizontal: AppSpacing.lg,
					vertical: AppSpacing.md,
				),
				hintStyle: base.textTheme.bodyMedium?.copyWith(
					color: AppColors.subtleText,
				),
				labelStyle: base.textTheme.bodySmall?.copyWith(
					color: AppColors.mutedText,
				),
				border: inputBorder,
				enabledBorder: inputBorder,
				focusedBorder: inputBorder.copyWith(
					borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
				),
				errorBorder: inputBorder.copyWith(
					borderSide: const BorderSide(color: AppColors.danger),
				),
				focusedErrorBorder: inputBorder.copyWith(
					borderSide: const BorderSide(color: AppColors.danger, width: 1.4),
				),
			),
			elevatedButtonTheme: ElevatedButtonThemeData(
				style: ElevatedButton.styleFrom(
					shape: RoundedRectangleBorder(
						borderRadius: BorderRadius.circular(AppRadii.md),
					),
					minimumSize: const Size(0, 48),
					elevation: 0,
					padding: const EdgeInsets.symmetric(
						horizontal: AppSpacing.lg,
						vertical: AppSpacing.md,
					),
				),
			),
			outlinedButtonTheme: OutlinedButtonThemeData(
				style: OutlinedButton.styleFrom(
					shape: RoundedRectangleBorder(
						borderRadius: BorderRadius.circular(AppRadii.md),
					),
					minimumSize: const Size(0, 48),
					side: const BorderSide(color: AppColors.border),
					padding: const EdgeInsets.symmetric(
						horizontal: AppSpacing.lg,
						vertical: AppSpacing.md,
					),
				),
			),
			textButtonTheme: TextButtonThemeData(
				style: TextButton.styleFrom(
					minimumSize: const Size(0, 48),
					shape: RoundedRectangleBorder(
						borderRadius: BorderRadius.circular(AppRadii.md),
					),
					padding: const EdgeInsets.symmetric(
						horizontal: AppSpacing.md,
						vertical: AppSpacing.sm,
					),
				),
			),
			switchTheme: SwitchThemeData(
				thumbColor: WidgetStateProperty.resolveWith((states) {
					if (states.contains(WidgetState.selected)) return AppColors.primary;
					return AppColors.surface;
				}),
				trackColor: WidgetStateProperty.resolveWith((states) {
					if (states.contains(WidgetState.selected)) {
						return AppColors.primarySoft;
					}
					return AppColors.border;
				}),
			),
			chipTheme: base.chipTheme.copyWith(
				backgroundColor: AppColors.placeholderAlt,
				shape: RoundedRectangleBorder(
					borderRadius: BorderRadius.circular(AppRadii.pill),
				),
				labelStyle: base.textTheme.labelSmall?.copyWith(
					color: AppColors.text,
					fontWeight: FontWeight.w700,
				),
			),
			bottomSheetTheme: const BottomSheetThemeData(
				backgroundColor: AppColors.surface,
				surfaceTintColor: Colors.transparent,
				showDragHandle: true,
				dragHandleColor: AppColors.border,
				shape: RoundedRectangleBorder(
					borderRadius: BorderRadius.vertical(
						top: Radius.circular(AppRadii.lg),
					),
				),
			),
			snackBarTheme: SnackBarThemeData(
				backgroundColor: AppColors.text,
				contentTextStyle: base.textTheme.bodySmall?.copyWith(
					color: Colors.white,
				),
				shape: RoundedRectangleBorder(
					borderRadius: BorderRadius.circular(AppRadii.md),
				),
				behavior: SnackBarBehavior.floating,
			),
			floatingActionButtonTheme: const FloatingActionButtonThemeData(
				backgroundColor: AppColors.primary,
				foregroundColor: Colors.white,
			),
			progressIndicatorTheme: const ProgressIndicatorThemeData(
				color: AppColors.primary,
			),
		);
	}
}
