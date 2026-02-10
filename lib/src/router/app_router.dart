import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_trial/src/features/auth/screens/auth_flow.dart';
import 'package:flutter_application_trial/src/features/feed/screens/feed_screen.dart';
import 'package:flutter_application_trial/src/features/friends/screens/friends_screen.dart';
import 'package:flutter_application_trial/src/features/profile/screens/profile_screen.dart';
import 'package:flutter_application_trial/src/features/profile/screens/profile_setup_screen.dart';
import 'package:flutter_application_trial/src/features/trips/screens/create_trip_screen.dart';
import 'package:flutter_application_trial/src/features/trips/screens/trip_detail_screen.dart';
import 'package:flutter_application_trial/src/features/trips/screens/trip_settings_screen.dart';
import 'package:flutter_application_trial/src/features/story/screens/story_detail_screen.dart';
import 'package:flutter_application_trial/src/features/invites/screens/invite_join_screen.dart';
import 'package:flutter_application_trial/src/features/home/screens/home_shell.dart';
import 'package:flutter_application_trial/src/providers.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();

final goRouterProvider = Provider<GoRouter>((ref) {
  final sessionAsync = ref.watch(authSessionProvider);
  final session = sessionAsync.value;
  final pendingInviteToken = ref.watch(pendingInviteTokenProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/home',
    routes: [
      GoRoute(path: '/', redirect: (context, state) => '/home'),
      GoRoute(path: '/auth', builder: (context, state) => const AuthFlow()),
      GoRoute(
        path: '/invite/:token',
        builder: (context, state) {
          final token = state.pathParameters['token'] ?? '';
          return InviteJoinScreen(inviteInput: token);
        },
      ),
      ShellRoute(
        builder: (context, state, child) {
          return HomeShell(location: state.uri.toString(), child: child);
        },
        routes: [
          GoRoute(
            path: '/home',
            builder: (context, state) =>
                const FeedScreen(initialTab: HomeTab.wall),
          ),
          GoRoute(
            path: '/trips',
            builder: (context, state) =>
                const FeedScreen(initialTab: HomeTab.trips),
          ),
          GoRoute(
            path: '/friends',
            builder: (context, state) => const FriendsScreen(),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      ),
      GoRoute(
        path: '/trips/create',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const CreateTripScreen(),
      ),
      GoRoute(
        path: '/profile/setup',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileSetupScreen(),
      ),
      GoRoute(
        path: '/trips/:tripId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final tripId = state.pathParameters['tripId'] ?? '';
          final tabName = state.uri.queryParameters['tab'];
          return TripDetailScreen(
            tripId: tripId,
            initialTab: tripDetailTabFromQuery(tabName),
          );
        },
      ),
      GoRoute(
        path: '/trips/:tripId/story',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final tripId = state.pathParameters['tripId'] ?? '';
          return StoryDetailScreen(tripId: tripId);
        },
      ),
      GoRoute(
        path: '/trips/:tripId/settings',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final tripId = state.pathParameters['tripId'] ?? '';
          return TripSettingsScreen(tripId: tripId);
        },
      ),
    ],
    redirect: (context, state) {
      final isAuthRoute = state.matchedLocation == '/auth';
      final isInviteRoute = state.matchedLocation.startsWith('/invite');

      if (sessionAsync.isLoading) {
        return null;
      }

      if (pendingInviteToken != null && !isInviteRoute) {
        return '/invite/$pendingInviteToken';
      }

      if (session == null) {
        if (isAuthRoute || isInviteRoute) {
          return null;
        }
        return '/auth';
      }

      if (isAuthRoute) {
        return '/home';
      }

      return null;
    },
  );
});
