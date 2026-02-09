import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/app_theme.dart';

class AppScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final bool showBack;
  final VoidCallback? onHome;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry? padding;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.showBack = true,
    this.onHome,
    this.actions,
    this.floatingActionButton,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final showLeading = showBack && canPop;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: title == null ? null : Text(title!),
        leading: showLeading ? const BackButton() : null,
        actions: [
          if (onHome != null)
            IconButton(
              icon: const Icon(Icons.home_outlined),
              onPressed: onHome,
            ),
          ...?actions,
        ],
      ),
      floatingActionButton: floatingActionButton,
      body: SafeArea(
        child: Padding(
          padding: padding ?? const EdgeInsets.all(AppSpacing.xl),
          child: body,
        ),
      ),
    );
  }
}
