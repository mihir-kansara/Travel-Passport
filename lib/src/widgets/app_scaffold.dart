import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/app_theme.dart';

class AppScaffold extends StatelessWidget {
  final Widget body;
  final String? title;
  final bool showBack;
  final bool showAppBar;
  final VoidCallback? onHome;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final EdgeInsetsGeometry? padding;
  final Widget? bottomNavigationBar;

  const AppScaffold({
    super.key,
    required this.body,
    this.title,
    this.showBack = true,
    this.showAppBar = true,
    this.onHome,
    this.actions,
    this.floatingActionButton,
    this.padding,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final showLeading = showBack && canPop;
    final appBar = showAppBar
        ? AppBar(
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
          )
        : null;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: SafeArea(
        child: Padding(
          padding: padding ??
              const EdgeInsets.fromLTRB(
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.xl,
              ),
          child: body,
        ),
      ),
    );
  }
}
