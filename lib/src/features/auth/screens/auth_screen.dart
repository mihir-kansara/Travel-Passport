import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';

class AuthScreen extends StatelessWidget {
  final VoidCallback onBack;
  final VoidCallback onGoogle;
  final VoidCallback onApple;
  final VoidCallback onDeveloper;
  final bool isLoading;
  final String? errorText;

  const AuthScreen({
    super.key,
    required this.onBack,
    required this.onGoogle,
    required this.onApple,
    required this.onDeveloper,
    this.isLoading = false,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      showAppBar: false,
      padding: EdgeInsets.zero,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surfaceAlt, AppColors.background],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.xl,
              AppSpacing.lg,
              AppSpacing.xl,
              AppSpacing.xxl,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(height: 16),
                Text(
                  'Sign in to continue',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Save your trips, invite friends, and sync everything across devices.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.mutedText,
                  ),
                ),
                const SizedBox(height: 32),
                _AuthButton(
                  label: 'Continue with Google',
                  icon: Icons.g_mobiledata,
                  onTap: isLoading ? null : onGoogle,
                  foreground: Colors.white,
                  background: AppColors.text,
                ),
                const SizedBox(height: 12),
                _AuthButton(
                  label: 'Continue with Apple',
                  icon: Icons.apple,
                  onTap: isLoading ? null : onApple,
                  foreground: Colors.white,
                  background: AppColors.text,
                ),
                const SizedBox(height: 12),
                _AuthButton(
                  label: 'Continue as guest',
                  icon: Icons.bolt,
                  onTap: isLoading ? null : onDeveloper,
                  foreground: AppColors.text,
                  background: AppColors.surfaceAlt,
                ),
                if (isLoading) ...[
                  const SizedBox(height: 16),
                  const Center(child: CircularProgressIndicator()),
                ],
                if (errorText != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    errorText!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.danger,
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  'We only use your profile to personalize the experience. No spam.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.subtleText,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AuthButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color foreground;
  final Color background;

  const _AuthButton({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onTap == null
            ? null
            : () {
                HapticFeedback.lightImpact();
                onTap?.call();
              },
        icon: Icon(icon, color: foreground),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
        ),
      ),
    );
  }
}
