import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/models/auth.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/models/friends.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/repositories/mock_repository.dart';
import 'package:flutter_application_trial/src/repositories/firestore_repository.dart';
import 'package:flutter_application_trial/src/analytics/app_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
});

final firebaseAnalyticsProvider = Provider<FirebaseAnalytics>((ref) {
  return FirebaseAnalytics.instance;
});

final appAnalyticsProvider = Provider<AppAnalytics>((ref) {
  return AppAnalytics(ref.watch(firebaseAnalyticsProvider));
});

/// Auth session provider (null means signed out).
final authSessionProvider = StreamProvider<AuthSession?>((ref) {
  final auth = ref.watch(firebaseAuthProvider);
  return auth.authStateChanges().map((user) {
    if (user == null) return null;
    return AuthSession(
      userId: user.uid,
      displayName: user.displayName ?? 'Traveler',
      email: user.email,
      avatarUrl: user.photoURL,
    );
  });
});

/// Repository provider — uses Firestore when signed in, otherwise fallback to mock.
final repositoryProvider = Provider<TripRepository>((ref) {
  final session = ref.watch(authSessionProvider).value;
  final userId = session?.userId;
  if (userId == null) {
    return MockTripRepository(currentUserId: 'user_1');
  }
  return FirestoreTripRepository(
    firestore: ref.watch(firestoreProvider),
    currentUserId: userId,
  );
});

/// Provider for fetching all trips for the current user.
final userTripsProvider = FutureProvider<List<Trip>>((ref) async {
  final repo = ref.watch(repositoryProvider);
  return repo.fetchUserTrips();
});

/// Provider for watching trips in real-time (alternative to FutureProvider).
final userTripsStreamProvider = StreamProvider<List<Trip>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchUserTrips();
});

/// Provider for a single trip by ID.
final tripByIdProvider = FutureProvider.family<Trip?, String>((
  ref,
  tripId,
) async {
  final repo = ref.watch(repositoryProvider);
  return repo.getTripById(tripId);
});

/// Provider for watching a single trip in real-time.
final tripStreamProvider = StreamProvider.family<Trip?, String>((ref, tripId) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchTrip(tripId);
});

/// Provider for itinerary items of a trip.
final tripItineraryProvider =
    FutureProvider.family<List<ItineraryItem>, String>((ref, tripId) async {
      final repo = ref.watch(repositoryProvider);
      return repo.getItinerary(tripId);
    });

/// Provider for watching itinerary items in real-time.
final tripItineraryStreamProvider =
    StreamProvider.family<List<ItineraryItem>, String>((ref, tripId) {
      final repo = ref.watch(repositoryProvider);
      return repo.watchItinerary(tripId);
    });

/// Provider for itinerary categories (canonical list).
final itineraryCategoriesProvider = FutureProvider<List<ItineraryCategory>>((
  ref,
) async {
  final repo = ref.watch(repositoryProvider);
  return repo.getItineraryCategories();
});

/// Provider for watching chat messages in real-time.
final tripChatStreamProvider =
    StreamProvider.family<List<ChatMessage>, String>((ref, tripId) {
      final repo = ref.watch(repositoryProvider);
      return repo.watchChatMessages(tripId);
    });

/// Provider for watching trip wall comments in real-time.
final tripCommentsStreamProvider =
    StreamProvider.family<List<WallComment>, String>((ref, tripId) {
      final repo = ref.watch(repositoryProvider);
      return repo.watchTripComments(tripId);
    });

/// Provider for watching itinerary item comments in real-time.
final itineraryCommentsStreamProvider =
    StreamProvider.family<List<ItineraryComment>, (String, String)>(
      (ref, params) {
        final (tripId, itemId) = params;
        final repo = ref.watch(repositoryProvider);
        return repo.watchItineraryComments(tripId, itemId);
      },
    );

/// Provider for a single user profile.
final userProfileProvider = FutureProvider.family<UserProfile?, String>(
  (ref, userId) async {
    final repo = ref.watch(repositoryProvider);
    return repo.getUserProfile(userId);
  },
);

/// Provider for current user's profile.
final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final session = ref.watch(authSessionProvider).value;
  if (session == null) return null;
  final repo = ref.watch(repositoryProvider);
  var profile = await repo.getUserProfile(session.userId);
  if (profile != null) return profile;
  final now = DateTime.now();
  final displayName = session.displayName.trim();
  final created = UserProfile(
    userId: session.userId,
    displayName: displayName,
    handle: null,
    email: session.email,
    phone: null,
    photoUrl: session.avatarUrl,
    bio: null,
    createdAt: now,
    updatedAt: now,
  );
  await repo.updateUserProfile(created);
  return created;
});

/// Provider for a map of user profiles keyed by userId.
final userProfilesProvider = FutureProvider.family<
    Map<String, UserProfile?>,
    List<String>>((ref, userIds) async {
  if (userIds.isEmpty) return {};
  final repo = ref.watch(repositoryProvider);
  final uniqueIds = userIds.toSet().toList();
  final profiles = await Future.wait(
    uniqueIds.map((userId) => repo.getUserProfile(userId)),
  );
  final map = <String, UserProfile?>{};
  for (var i = 0; i < uniqueIds.length; i++) {
    map[uniqueIds[i]] = profiles[i];
  }
  return map;
});

/// Provider for searching user profiles.
final friendSearchProvider = FutureProvider.family<List<UserProfile>, String>(
  (ref, query) async {
    final repo = ref.watch(repositoryProvider);
    return repo.searchUserProfiles(query);
  },
);

/// Provider for watching friends.
final friendsProvider = StreamProvider<List<Friendship>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchFriends();
});

/// Provider for incoming friend requests.
final incomingFriendRequestsProvider =
    StreamProvider<List<FriendRequest>>((ref) {
      final repo = ref.watch(repositoryProvider);
      return repo.watchIncomingFriendRequests();
    });

/// Provider for outgoing friend requests.
final outgoingFriendRequestsProvider =
    StreamProvider<List<FriendRequest>>((ref) {
      final repo = ref.watch(repositoryProvider);
      return repo.watchOutgoingFriendRequests();
    });

/// Provider for blocked users.
final blockedUsersProvider = StreamProvider<List<BlockedUser>>((ref) {
  final repo = ref.watch(repositoryProvider);
  return repo.watchBlockedUsers();
});

/// Provider for an itinerary item by ID (filtered from trip itinerary).
final itineraryItemProvider =
    FutureProvider.family<ItineraryItem?, (String, String)>((
      ref,
      params,
    ) async {
      final (tripId, itemId) = params;
      final items = await ref.watch(tripItineraryProvider(tripId).future);
      try {
        return items.firstWhere((item) => item.id == itemId);
      } catch (e) {
        return null;
      }
    });

/// Selected trip ID for detail view (state).
final selectedTripIdProvider = StateProvider<String?>((ref) => null);

/// Pending invite token from a deep link.
final pendingInviteTokenProvider = StateProvider<String?>((ref) => null);

/// Currently viewed trip (derived from selectedTripIdProvider).
final currentTripProvider = FutureProvider<Trip?>((ref) {
  final tripId = ref.watch(selectedTripIdProvider);
  if (tripId == null) return Future.value(null);
  return ref.watch(tripByIdProvider(tripId).future);
});

/// Provider for creating a new trip.
final createTripProvider = FutureProvider.family<Trip, CreateTripParams>((
  ref,
  params,
) async {
  final repo = ref.watch(repositoryProvider);
  return repo.createTrip(
    destination: params.destination,
    startDate: params.startDate,
    endDate: params.endDate,
    description: params.description,
    heroImageUrl: params.heroImageUrl,
    coverGradientId: params.coverGradientId,
    visibility: params.visibility,
  );
});

/// Provider for invites.
final createInviteProvider =
    FutureProvider.family<Invite, (String, String?, MemberRole)>(
  (ref, params) async {
    final (tripId, email, role) = params;
    final repo = ref.watch(repositoryProvider);
    return repo.createInvite(tripId: tripId, invitedEmail: email, role: role);
  },
);

/// Parameters for creating a trip.
class CreateTripParams {
  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final String description;
  final String? heroImageUrl;
  final int? coverGradientId;
  final TripVisibility visibility;

  CreateTripParams({
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.description,
    this.heroImageUrl,
    this.coverGradientId,
    this.visibility = TripVisibility.inviteOnly,
  });
}
