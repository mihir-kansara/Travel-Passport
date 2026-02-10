import 'dart:async';

import 'package:flutter/material.dart';
import 'package:app_links/app_links.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/app_config.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/router/app_router.dart';
import 'package:flutter_application_trial/src/utils/invite_utils.dart';
import 'package:flutter_application_trial/src/utils/app_logger.dart';

class AppEntry extends ConsumerStatefulWidget {
  const AppEntry({super.key});

  @override
  ConsumerState<AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends ConsumerState<AppEntry> {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;
  bool _restoredPendingInvite = false;

  @override
  void initState() {
    super.initState();
    _restorePendingInvite();
    _initDeepLinks();
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
    AppLogger.info(
      'Deep link received',
      name: 'deep_link',
      error: uri.toString(),
    );
    final token = parseInviteTokenFromUri(uri);
    if (token == null) {
      AppLogger.info('Deep link ignored (no token)', name: 'deep_link');
      return;
    }
    ref.read(pendingInviteTokenProvider.notifier).state = token;
    ref.read(appAnalyticsProvider).logInviteDeepLink(token: token);
    unawaited(InviteTokenStore.savePendingToken(token));
  }

  @override
  void dispose() {
    _linkSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(goRouterProvider);
    return MaterialApp.router(
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      title: AppConfig.appName,
      theme: AppTheme.lightTheme(),
    );
  }
}
