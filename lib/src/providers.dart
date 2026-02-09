import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/models/auth.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/repositories/mock_repository.dart';
import 'package:flutter_application_trial/src/repositories/firestore_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

final firestoreProvider = Provider<FirebaseFirestore>((ref) {
  return FirebaseFirestore.instance;
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
final createInviteProvider = FutureProvider.family<Invite, (String, String?)>((
  ref,
  params,
) async {
  final (tripId, email) = params;
  final repo = ref.watch(repositoryProvider);
  return repo.createInvite(tripId: tripId, invitedEmail: email);
});

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
