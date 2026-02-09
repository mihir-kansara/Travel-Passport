import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:flutter_application_trial/src/screens/welcome_screen.dart';
import 'package:flutter_application_trial/src/screens/auth_screen.dart';

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
      if (googleUser == null) {
        _setLoading(false);
        return;
      }
      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final auth = FirebaseAuth.instance;
      final currentUser = auth.currentUser;
      if (currentUser != null && currentUser.isAnonymous) {
        await currentUser.linkWithCredential(credential);
      } else {
        await auth.signInWithCredential(credential);
      }
      _setLoading(false);
    } catch (e) {
      _setError('Google sign-in failed. Try again.');
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
      _setLoading(false);
    } catch (e) {
      _setError('Apple sign-in failed. Try again.');
    }
  }

  Future<void> _signInAsDeveloper() async {
    _setLoading(true);
    try {
      await FirebaseAuth.instance.signInAnonymously();
      _setLoading(false);
    } catch (e) {
      _setError('Developer sign-in failed. Enable Anonymous auth.');
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
