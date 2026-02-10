import 'package:flutter/material.dart';
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
            colors: [Color(0xFFF8FAFC), Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
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
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 32),
                _AuthButton(
                  label: 'Continue with Google',
                  icon: Icons.g_mobiledata,
                  onTap: isLoading ? null : onGoogle,
                  foreground: Colors.white,
                  background: const Color(0xFF0F172A),
                ),
                const SizedBox(height: 12),
                _AuthButton(
                  label: 'Continue with Apple',
                  icon: Icons.apple,
                  onTap: isLoading ? null : onApple,
                  foreground: Colors.white,
                  background: const Color(0xFF1F2937),
                ),
                const SizedBox(height: 12),
                _AuthButton(
                  label: 'Continue as guest',
                  icon: Icons.bolt,
                  onTap: isLoading ? null : onDeveloper,
                  foreground: const Color(0xFF0F172A),
                  background: const Color(0xFFE2E8F0),
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
                      color: const Color(0xFFDC2626),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  'We only use your profile to personalize the experience. No spam.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
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
        onPressed: onTap,
        icon: Icon(icon, color: foreground),
        label: Text(label),
        style: ElevatedButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
