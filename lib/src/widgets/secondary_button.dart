import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_trial/src/app_theme.dart';

class SecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool isCompact;
  final bool fullWidth;

  const SecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.isCompact = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final onTap = onPressed == null
        ? null
        : () {
            HapticFeedback.selectionClick();
            onPressed?.call();
          };
    final padding = EdgeInsets.symmetric(
      vertical: isCompact ? AppSpacing.sm : AppSpacing.lg,
      horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
    );
    if (icon != null) {
      return SizedBox(
        width: fullWidth ? double.infinity : null,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, color: AppColors.text),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            padding: padding,
            side: const BorderSide(color: AppColors.border),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.text,
          padding: padding,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
        child: Text(label),
      ),
    );
  }
}
