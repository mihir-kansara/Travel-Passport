import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/app_config.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/features/auth/screens/auth_flow.dart';
import 'package:flutter_application_trial/src/features/home/screens/home_shell.dart';
import 'package:flutter_application_trial/src/features/invites/screens/invite_join_screen.dart';
import 'package:flutter_application_trial/src/features/profile/screens/profile_setup_screen.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/utils/profile_utils.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/utils/invite_utils.dart';

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
    final token = parseInviteTokenFromUri(uri);
    if (token == null) return;
    ref.read(pendingInviteTokenProvider.notifier).state = token;
    unawaited(InviteTokenStore.savePendingToken(token));
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
  bool _restoredPendingInvite = false;

  @override
  void initState() {
    super.initState();
    _restorePendingInvite();
  }

  Future<void> _restorePendingInvite() async {
    if (_restoredPendingInvite) return;
    _restoredPendingInvite = true;
    final stored = await InviteTokenStore.loadPendingToken();
    if (!mounted || stored == null) return;
    final current = ref.read(pendingInviteTokenProvider);
    if (current == null) {
      ref.read(pendingInviteTokenProvider.notifier).state = stored;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(authSessionProvider);
    final pendingInviteToken = ref.watch(pendingInviteTokenProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);

    return sessionAsync.when(
      data: (session) {
        if (session == null) {
          return const AuthFlow();
        }
        return profileAsync.when(
          data: (profile) {
            final isComplete = profile != null &&
                isValidDisplayName(profile.displayName);
            if (!isComplete) {
              return const ProfileSetupScreen();
            }
            if (pendingInviteToken != null &&
                pendingInviteToken != _lastInviteToken) {
              _lastInviteToken = pendingInviteToken;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                showGuardedSnackBar(context, 'Invite detected.');
                ref.read(pendingInviteTokenProvider.notifier).state = null;
                unawaited(InviteTokenStore.clearPendingToken());
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => InviteJoinScreen(
                      inviteInput: pendingInviteToken,
                    ),
                  ),
                );
              });
            }
            return const HomeShell();
          },
          loading: () => const AppScaffold(
            showAppBar: false,
            body: Center(child: CircularProgressIndicator()),
          ),
          error: (e, st) => AppScaffold(
            showAppBar: false,
            body: Center(child: Text('Profile error: $e')),
          ),
        );
      },
      loading: () => const AppScaffold(
        showAppBar: false,
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, st) => AppScaffold(
        showAppBar: false,
        body: Center(child: Text('Auth error: $e')),
      ),
    );
  }
}
