import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_application_trial/src/features/auth/screens/welcome_screen.dart';
import 'package:flutter_application_trial/src/features/auth/screens/auth_screen.dart';
import 'package:flutter_application_trial/src/utils/app_logger.dart';

class AuthFlow extends ConsumerStatefulWidget {
  const AuthFlow({super.key});

  @override
  ConsumerState<AuthFlow> createState() => _AuthFlowState();
}

class _AuthFlowState extends ConsumerState<AuthFlow> {
  bool _showAuth = false;
  bool _isLoading = false;
  String? _errorText;

  @override
  Widget build(BuildContext context) {
    if (_showAuth) {
      return AuthScreen(
        onBack: () => setState(() => _showAuth = false),
        onGoogle: _signInWithGoogle,
        onApple: _signInWithApple,
        onDeveloper: _signInAsDeveloper,
        isLoading: _isLoading,
        errorText: _errorText,
      );
    }

    return WelcomeScreen(onContinue: () => setState(() => _showAuth = true));
  }

  Future<void> _signInWithGoogle() async {
    _setLoading(true);
    try {
      final googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final googleAuth = await googleUser.authentication;
      if (googleAuth.idToken == null) {
        throw StateError('Missing Google ID token.');
      }
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser != null && currentUser.isAnonymous) {
        try {
          await currentUser.linkWithCredential(credential);
        } on FirebaseAuthException catch (e) {
          if (e.code == 'credential-already-in-use' ||
              e.code == 'provider-already-linked') {
            await auth.signInWithCredential(credential);
          } else {
            rethrow;
          }
        }
      } else {
        await auth.signInWithCredential(credential);
      }
    } on FirebaseAuthException catch (e, stackTrace) {
      AppLogger.error(
        'Google sign-in failed.',
        name: 'AuthFlow',
        error: e,
        stackTrace: stackTrace,
      );
      _setError(_messageForFirebaseAuthError(e));
    } on PlatformException catch (e, stackTrace) {
      AppLogger.error(
        'Google sign-in failed.',
        name: 'AuthFlow',
        error: e,
        stackTrace: stackTrace,
      );
      _setError(_messageForPlatformError(e));
    } catch (e, stackTrace) {
      AppLogger.error(
        'Google sign-in failed.',
        name: 'AuthFlow',
        error: e,
        stackTrace: stackTrace,
      );
      _setError('Google sign-in failed. Try again.');
    } finally {
      if (mounted) {
        _setLoading(false);
      }
    }
  }

  Future<void> _signInWithApple() async {
    _setLoading(true);
    try {
      final provider = AppleAuthProvider();
      provider.addScope('email');
      provider.addScope('name');
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser != null && currentUser.isAnonymous) {
        await currentUser.linkWithProvider(provider);
      } else {
        await auth.signInWithProvider(provider);
      }
    } catch (e, stackTrace) {
      AppLogger.error(
        'Apple sign-in failed.',
        name: 'AuthFlow',
        error: e,
        stackTrace: stackTrace,
      );
      _setError('Apple sign-in failed. Try again.');
    } finally {
      if (mounted) {
        _setLoading(false);
      }
    }
  }

  Future<void> _signInAsDeveloper() async {
    _setLoading(true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
    } catch (e, stackTrace) {
      AppLogger.error(
        'Guest sign-in failed.',
        name: 'AuthFlow',
        error: e,
        stackTrace: stackTrace,
      );
      _setError('Guest sign-in failed. Enable Anonymous auth.');
    } finally {
      if (mounted) {
        _setLoading(false);
      }
    }
  }

  String _messageForFirebaseAuthError(FirebaseAuthException error) {
    switch (error.code) {
      case 'account-exists-with-different-credential':
        return 'Account exists with a different sign-in method.';
      case 'credential-already-in-use':
        return 'That Google account is already linked. Try signing in.';
      case 'invalid-credential':
        return 'Google credentials are invalid. Try again.';
      case 'operation-not-allowed':
        return 'Google sign-in is not enabled for this project.';
      case 'user-disabled':
        return 'This user account is disabled.';
      default:
        return 'Google sign-in failed. Try again.';
    }
  }

  String _messageForPlatformError(PlatformException error) {
    switch (error.code) {
      case 'network_error':
        return 'Network error. Check your connection and try again.';
      case 'sign_in_failed':
        return 'Google sign-in failed. Check the app configuration.';
      case 'sign_in_required':
        return 'Google sign-in is required to continue.';
      default:
        return 'Google sign-in failed. Try again.';
    }
  }

  void _setLoading(bool value) {
    setState(() {
      _isLoading = value;
      if (value) {
        _errorText = null;
      }
    });
  }

  void _setError(String message) {
    setState(() {
      _isLoading = false;
      _errorText = message;
    });
  }
}
