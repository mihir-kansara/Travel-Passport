import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/app_config.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/screens/auth_flow.dart';
import 'package:flutter_application_trial/src/screens/home_shell.dart';
import 'package:flutter_application_trial/src/screens/invite_join_screen.dart';
import 'package:flutter_application_trial/src/theme.dart';

class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key});

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<AppEntry> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  Future<void> _initDeepLinks() async {
    try {
      final initialLink = await _appLinks.getInitialLink();
      _handleDeepLink(initialLink);
      _linkSubscription = _appLinks.uriLinkStream.listen(
        _handleDeepLink,
        onError: (_) {},
      );
    } catch (_) {}
  }

  void _handleDeepLink(Uri? uri) {
    if (uri == null) return;
    final token = _extractInviteToken(uri);
    if (token == null) return;
    ref.read(pendingInviteTokenProvider.notifier).state = token;
  }

  String? _extractInviteToken(Uri uri) {
    // TODO(travel-passport): Host an apple-app-site-association file for universal links.
    final tokenParam = uri.queryParameters['token'];
    if (tokenParam != null && tokenParam.isNotEmpty) return tokenParam;
    if (uri.scheme == 'travelpassport' && uri.host == 'invite') {
      return uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
    }
    if ((uri.scheme == 'https' || uri.scheme == 'http') &&
        uri.host == 'travelpassport.app' &&
        uri.pathSegments.isNotEmpty &&
        uri.pathSegments.first == 'invite') {
      return uri.pathSegments.length > 1 ? uri.pathSegments[1] : null;
    }
    return null;
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: AppTheme.lightTheme(),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});

  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  String? _lastInviteToken;

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(authSessionProvider);
    final pendingInviteToken = ref.watch(pendingInviteTokenProvider);

    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          return const AuthFlow();
        }
        if (pendingInviteToken != null &&
            pendingInviteToken != _lastInviteToken) {
          _lastInviteToken = pendingInviteToken;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            ref.read(pendingInviteTokenProvider.notifier).state = null;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => InviteJoinScreen(token: pendingInviteToken),
              ),
            );
          });
        }
        return const HomeShell();
      },
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('Auth error: $e'))),
    );
  }
}
