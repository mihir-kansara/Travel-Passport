import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/app_theme.dart';

class LoadingPlaceholder extends StatelessWidget {
  final int itemCount;
  final double itemHeight;
  final double radius;
  final EdgeInsets padding;

  const LoadingPlaceholder({
    super.key,
    this.itemCount = 3,
    this.itemHeight = 160,
    this.radius = AppRadii.md,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding.copyWith(top: AppSpacing.lg, bottom: AppSpacing.xl),
      itemCount: itemCount,
      separatorBuilder: (context, index) =>
          const SizedBox(height: AppSpacing.lg),
      itemBuilder: (context, index) {
        return Container(
          height: itemHeight,
          decoration: BoxDecoration(
            color: AppColors.placeholder,
            borderRadius: BorderRadius.circular(radius),
          ),
        );
      },
    );
  }
}
