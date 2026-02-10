import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/models/friends.dart';

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

  /// Update a member role in the trip (owner only).
  Future<void> updateMemberRole(String tripId, String userId, MemberRole role);

  /// Add or update an itinerary item.
  Future<ItineraryItem> upsertItineraryItem(String tripId, ItineraryItem item);

  /// Delete an itinerary item.
  Future<void> deleteItineraryItem(String tripId, String itemId);

  /// Reorder itinerary items within a day.
  Future<void> reorderItineraryItems(String tripId, List<ItineraryItem> items);

  /// Get itinerary items for a trip, optionally filtered by day.
  Future<List<ItineraryItem>> getItinerary(String tripId, {DateTime? day});

  /// Create an invite link for the trip.
  Future<Invite> createInvite({
    required String tripId,
    String? invitedEmail,
    MemberRole role = MemberRole.viewer,
  });

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

  /// Add or update a shared checklist item.
  Future<void> upsertSharedChecklistItem(String tripId, ChecklistItem item);

  /// Delete a shared checklist item.
  Future<void> deleteSharedChecklistItem(String tripId, String itemId);

  /// Add or update a personal checklist item for a member.
  Future<void> upsertPersonalChecklistItem(
    String tripId,
    String ownerUserId,
    ChecklistItem item,
  );

  /// Delete a personal checklist item for a member.
  Future<void> deletePersonalChecklistItem(
    String tripId,
    String ownerUserId,
    String itemId,
  );

  /// Update personal checklist visibility for a member.
  Future<void> setPersonalChecklistVisibility(
    String tripId,
    String ownerUserId,
    bool isShared,
  );

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

  /// Fetch itinerary categories (canonical list).
  Future<List<ItineraryCategory>> getItineraryCategories();

  /// Get or create user profile.
  Future<UserProfile?> getUserProfile(String userId);

  /// Update user profile.
  Future<void> updateUserProfile(UserProfile profile);

  /// Search user profiles by available identity (name/email/handle/phone).
  Future<List<UserProfile>> searchUserProfiles(String query);

  /// Stream friends for the current user.
  Stream<List<Friendship>> watchFriends();

  /// Stream incoming friend requests (pending).
  Stream<List<FriendRequest>> watchIncomingFriendRequests();

  /// Stream outgoing friend requests (pending).
  Stream<List<FriendRequest>> watchOutgoingFriendRequests();

  /// Send a friend request to another user.
  Future<void> sendFriendRequest(String toUserId);

  /// Respond to a friend request.
  Future<void> respondToFriendRequest(
    String requestId,
    FriendRequestStatus status,
  );

  /// Cancel a friend request that you sent.
  Future<void> cancelFriendRequest(String requestId);

  /// Remove an existing friend relationship.
  Future<void> removeFriend(String friendUserId);

  /// Block a user.
  Future<void> blockUser(String blockedUserId);

  /// Unblock a user.
  Future<void> unblockUser(String blockedUserId);

  /// Stream blocked users for the current user.
  Stream<List<BlockedUser>> watchBlockedUsers();
}

class ChatMessagesCursor {
  final DateTime createdAt;
  final String messageId;

  const ChatMessagesCursor({required this.createdAt, required this.messageId});
}

/// User profile information.
class UserProfile {
  final String userId;
  final String displayName;
  final String? handle;
  final String? email;
  final String? phone;
  final String? photoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile({
    required this.userId,
    required this.displayName,
    this.handle,
    this.email,
    this.phone,
    this.photoUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a copy with modified fields.
  UserProfile copyWith({
    String? userId,
    String? displayName,
    String? handle,
    String? email,
    String? phone,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      handle: handle ?? this.handle,
      email: email ?? this.email,
      phone: phone ?? this.phone,
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
    if (handle != null) {
      data['handle'] = handle;
    }
    if (email != null) {
      data['email'] = email;
    }
    if (phone != null) {
      data['phone'] = phone;
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
      handle: (data['handle'] ?? data['username']) as String?,
      email: data['email'] as String?,
      phone: (data['phone'] ?? data['phoneNumber']) as String?,
      photoUrl: (data['photoUrl'] ?? data['avatarUrl']) as String?,
      createdAt: parseTimestamp(data['createdAt']),
      updatedAt: parseTimestamp(data['updatedAt']),
    );
  }
}
