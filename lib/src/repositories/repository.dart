import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_trial/src/models/trip.dart';

/// Abstract repository for Trip data operations.
abstract class TripRepository {
  /// Fetch all trips for the current user (active, upcoming, past).
  Future<List<Trip>> fetchUserTrips();

  /// Fetch a single trip by ID (if user has access).
  Future<Trip?> getTripById(String tripId);

  /// Create a new trip.
  Future<Trip> createTrip({
    required String destination,
    required DateTime startDate,
    required DateTime endDate,
    required String description,
    String? heroImageUrl,
    int? coverGradientId,
    TripVisibility visibility = TripVisibility.inviteOnly,
  });

  /// Update an existing trip.
  Future<Trip> updateTrip(Trip trip);

  /// Delete a trip (owner only).
  Future<void> deleteTrip(String tripId);

  /// Add a member to the trip (owner only).
  Future<void> addMember(String tripId, Member member);

  /// Remove a member from the trip (owner only).
  Future<void> removeMember(String tripId, String userId);

  /// Add or update an itinerary item.
  Future<ItineraryItem> upsertItineraryItem(String tripId, ItineraryItem item);

  /// Delete an itinerary item.
  Future<void> deleteItineraryItem(String tripId, String itemId);

  /// Reorder itinerary items within a day.
  Future<void> reorderItineraryItems(
    String tripId,
    List<ItineraryItem> items,
  );

  /// Get itinerary items for a trip, optionally filtered by day.
  Future<List<ItineraryItem>> getItinerary(String tripId, {DateTime? day});

  /// Create an invite link for the trip.
  Future<Invite> createInvite({required String tripId, String? invitedEmail});

  /// Get invite by token (for joining a trip).
  Future<Invite?> getInviteByToken(String token);

  /// Mark invite as used.
  Future<void> markInviteAsUsed(String inviteId);

  /// Publish trip as a public story (or update published state).
  Future<void> publishTrip(String tripId, bool isPublished);

  /// Publish or remove trip from wall feed.
  Future<void> publishToWall(String tripId, bool publish);

  /// Add a like to the trip wall stats.
  Future<void> likeTrip(String tripId);

  /// Set a like state for the current user.
  Future<void> setTripLike(String tripId, bool liked);

  /// Add a comment to the trip wall.
  Future<void> addWallComment(String tripId, WallComment comment);

  /// Stream trip wall comments.
  Stream<List<WallComment>> watchTripComments(String tripId, {int limit});

  /// Send a chat message within a trip.
  Future<void> sendChatMessage(String tripId, ChatMessage message);

  /// Stream chat messages in descending order (latest last in returned list).
  Stream<List<ChatMessage>> watchChatMessages(String tripId, {int limit});

  /// Fetch older chat messages before the provided cursor.
  Future<List<ChatMessage>> fetchChatMessagesPage(
    String tripId, {
    int limit,
    ChatMessagesCursor? before,
  });

  /// Stream comments for a specific itinerary item.
  Stream<List<ItineraryComment>> watchItineraryComments(
    String tripId,
    String itemId,
  );

  /// Add a comment for a specific itinerary item.
  Future<void> addItineraryComment(
    String tripId,
    String itemId,
    ItineraryComment comment,
  );

  /// Update a member checklist entry.
  Future<void> updateMemberChecklist(String tripId, MemberChecklist checklist);

  /// Add or update a shared checklist item.
  Future<void> upsertSharedChecklistItem(String tripId, ChecklistItem item);

  /// Delete a shared checklist item.
  Future<void> deleteSharedChecklistItem(String tripId, String itemId);

  /// Request to join a trip.
  Future<void> requestToJoin(String tripId, JoinRequest request);

  /// Respond to a join request.
  Future<void> respondToJoinRequest(
    String tripId,
    String requestId,
    JoinRequestStatus status,
  );

  /// Stream of trips for real-time updates.
  Stream<List<Trip>> watchUserTrips();

  /// Stream of a single trip for real-time updates.
  Stream<Trip?> watchTrip(String tripId);

  /// Stream of itinerary items for real-time updates.
  Stream<List<ItineraryItem>> watchItinerary(String tripId);

  /// Get or create user profile.
  Future<UserProfile?> getUserProfile(String userId);

  /// Update user profile.
  Future<void> updateUserProfile(UserProfile profile);
}

class ChatMessagesCursor {
  final DateTime createdAt;
  final String messageId;

  const ChatMessagesCursor({
    required this.createdAt,
    required this.messageId,
  });
}

/// User profile information.
class UserProfile {
  final String userId;
  final String displayName;
  final String? email;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.userId,
    required this.displayName,
    this.email,
    this.photoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a copy with modified fields.
  UserProfile copyWith({
    String? userId,
    String? displayName,
    String? email,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Convert to Firestore document map.
  Map<String, dynamic> toFirestore() {
    final data = <String, dynamic>{
      'userId': userId,
      'displayName': displayName,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
    if (email != null) {
      data['email'] = email;
    }
    if (photoUrl != null) {
      data['photoUrl'] = photoUrl;
    }
    return data;
  }

  /// Create from Firestore document map.
  factory UserProfile.fromFirestore(Map<String, dynamic> data) {
    DateTime parseTimestamp(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      }
      if (value is DateTime) {
        return value;
      }
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return UserProfile(
      userId: data['userId'] as String? ?? '',
      displayName: data['displayName'] as String? ?? '',
      email: data['email'] as String?,
      photoUrl: (data['photoUrl'] ?? data['avatarUrl']) as String?,
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }
}
