import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_trial/src/app_theme.dart';

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;
  final bool isCompact;
  final bool fullWidth;

  const PrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
    this.isCompact = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    final onTap = isLoading || onPressed == null
        ? null
        : () {
            HapticFeedback.lightImpact();
            onPressed?.call();
          };
    final padding = EdgeInsets.symmetric(
      vertical: isCompact ? AppSpacing.sm : AppSpacing.lg,
      horizontal: isCompact ? AppSpacing.md : AppSpacing.lg,
    );
    final child = isLoading
        ? const SizedBox(
            height: 18,
            width: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          )
        : Text(label);

    if (icon != null && !isLoading) {
      return SizedBox(
        width: fullWidth ? double.infinity : null,
        child: ElevatedButton.icon(
          onPressed: onTap,
          icon: Icon(icon, color: Colors.white),
          label: child,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: padding,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.md),
            ),
          ),
        ),
      );
    }

    return SizedBox(
      width: fullWidth ? double.infinity : null,
      child: ElevatedButton(
        onPressed: onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: padding,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
        child: child,
      ),
    );
  }
}
