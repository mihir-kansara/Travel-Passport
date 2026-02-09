import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';

/// Firestore implementation of TripRepository for real-time, cloud-backed trips.
class FirestoreTripRepository implements TripRepository {
  final FirebaseFirestore firestore;
  final String currentUserId;

  FirestoreTripRepository({
    required this.firestore,
    required this.currentUserId,
  });

  CollectionReference<Map<String, dynamic>> get _trips =>
      firestore.collection('trips');
  CollectionReference<Map<String, dynamic>> get _invites =>
      firestore.collection('invites');
  CollectionReference<Map<String, dynamic>> get _users =>
      firestore.collection('users');

  TripUpdate _buildUpdate({
    String? actorId,
    required String text,
    required TripUpdateKind kind,
  }) {
    return TripUpdate(
      id: const Uuid().v4(),
      actorId: actorId ?? currentUserId,
      text: text,
      kind: kind,
      createdAt: DateTime.now(),
    );
  }

  Trip _withUpdate(Trip trip, TripUpdate update) {
    return trip.copyWith(
      updates: [update, ...trip.updates],
      updatedAt: DateTime.now(),
    );
  }

  Map<String, dynamic> _serializeTrip(Trip trip) {
    return {
      ...trip.toJson(),
      'id': trip.id,
      'memberIds': trip.members.map((m) => m.userId).toList(),
    };
  }

  Trip? _deserializeTrip(DocumentSnapshot<Map<String, dynamic>> doc) {
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return Trip.fromJson({...data, 'id': data['id'] ?? doc.id});
  }

  Future<void> _saveTrip(Trip trip) async {
    await _trips.doc(trip.id).set(_serializeTrip(trip));
  }

  @override
  Future<List<Trip>> fetchUserTrips() async {
    final snapshot = await _trips
        .where('memberIds', arrayContains: currentUserId)
        .get();
    return snapshot.docs.map(_deserializeTrip).whereType<Trip>().toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<Trip?> getTripById(String tripId) async {
    final doc = await _trips.doc(tripId).get();
    final trip = _deserializeTrip(doc);
    if (trip == null) return null;
    final isMember = trip.members.any((m) => m.userId == currentUserId);
    return isMember ? trip : null;
  }

  @override
  Future<Trip> createTrip({
    required String destination,
    required DateTime startDate,
    required DateTime endDate,
    required String description,
    String? heroImageUrl,
    int? coverGradientId,
    TripVisibility visibility = TripVisibility.inviteOnly,
  }) async {
    final now = DateTime.now();
    final doc = _trips.doc();
    final update = _buildUpdate(
      text: 'Trip created. Invite your people and start planning.',
      kind: TripUpdateKind.system,
    );
    final trip = Trip(
      id: doc.id,
      ownerId: currentUserId,
      destination: destination,
      startDate: startDate,
      endDate: endDate,
      description: description,
      visibility: visibility,
      audience: TripAudience(visibility: visibility),
      members: [
        Member(
          userId: currentUserId,
          name: 'You',
          role: MemberRole.owner,
          joinedAt: now,
        ),
      ],
      itinerary: const [],
      checklist: TripChecklist(
        members: [MemberChecklist(userId: currentUserId, updatedAt: now)],
      ),
      updates: [update],
      createdAt: now,
      updatedAt: now,
      heroImageUrl: heroImageUrl,
      coverGradientId: coverGradientId,
    );
    await _saveTrip(trip);
    return trip;
  }

  @override
  Future<Trip> updateTrip(Trip trip) async {
    // TODO(travel-passport): Use patch updates to avoid overwriting large docs.
    final updated = trip.copyWith(updatedAt: DateTime.now());
    await _saveTrip(updated);
    return updated;
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    await _trips.doc(tripId).delete();
  }

  @override
  Future<void> addMember(String tripId, Member member) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final exists = trip.members.any((m) => m.userId == member.userId);
    if (exists) return;
    final updated = trip.copyWith(
      members: [...trip.members, member],
      updatedAt: DateTime.now(),
    );
    final updatedChecklist = _upsertMemberChecklist(
      trip.checklist,
      MemberChecklist(userId: member.userId, updatedAt: DateTime.now()),
    );
    final update = _buildUpdate(
      actorId: member.userId,
      text: '${member.name} joined the trip.',
      kind: TripUpdateKind.people,
    );
    await _saveTrip(
      _withUpdate(updated.copyWith(checklist: updatedChecklist), update),
    );
  }

  @override
  Future<void> removeMember(String tripId, String userId) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedChecklist = trip.checklist.copyWith(
      members: trip.checklist.members.where((m) => m.userId != userId).toList(),
    );
    await _saveTrip(
      trip.copyWith(
        members: trip.members.where((m) => m.userId != userId).toList(),
        checklist: updatedChecklist,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<ItineraryItem> upsertItineraryItem(
    String tripId,
    ItineraryItem item,
  ) async {
    // TODO(travel-passport): Move itinerary to a subcollection to reduce doc contention.
    final docRef = _trips.doc(tripId);
    return firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final trip = _deserializeTrip(snapshot);
      if (trip == null) return item;
      final existingIndex = trip.itinerary.indexWhere((i) => i.id == item.id);
      final existingItem = existingIndex >= 0
          ? trip.itinerary[existingIndex]
          : null;
      final updated = [...trip.itinerary];
      String updateText;
      var nextItem = item;
      if (existingIndex >= 0) {
        updated[existingIndex] = item;
        if (existingItem != null &&
            existingItem.isCompleted != item.isCompleted) {
          updateText = item.isCompleted
              ? 'Completed: ${item.title}.'
              : 'Reopened: ${item.title}.';
        } else {
          updateText = 'Updated ${item.type.name}: ${item.title}.';
        }
      } else {
        final nextOrder = _nextOrderForDay(trip, item.dateTime);
        nextItem = item.copyWith(order: nextOrder);
        updated.add(nextItem);
        updateText = 'Added ${item.type.name}: ${item.title}.';
      }
      final updatedTrip = trip.copyWith(
        itinerary: updated,
        updatedAt: DateTime.now(),
      );
      final update = _buildUpdate(
        text: updateText,
        kind: TripUpdateKind.planner,
      );
      transaction.set(docRef, _serializeTrip(_withUpdate(updatedTrip, update)));
      return nextItem;
    });
  }

  int _nextOrderForDay(Trip trip, DateTime dateTime) {
    final sameDay = trip.itinerary.where(
      (item) =>
          item.dateTime.year == dateTime.year &&
          item.dateTime.month == dateTime.month &&
          item.dateTime.day == dateTime.day,
    );
    var maxOrder = -1;
    for (final item in sameDay) {
      if (item.order > maxOrder) {
        maxOrder = item.order;
      }
    }
    return maxOrder + 1;
  }

  @override
  Future<void> deleteItineraryItem(String tripId, String itemId) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final removedItem = trip.itinerary.firstWhere(
      (i) => i.id == itemId,
      orElse: () => ItineraryItem(
        id: itemId,
        tripId: tripId,
        dateTime: DateTime.now(),
        title: 'An item',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    final updated = trip.copyWith(
      itinerary: trip.itinerary.where((i) => i.id != itemId).toList(),
      updatedAt: DateTime.now(),
    );
    final update = _buildUpdate(
      text: 'Removed ${removedItem.title} from the plan.',
      kind: TripUpdateKind.planner,
    );
    await _saveTrip(_withUpdate(updated, update));
  }

  @override
  Future<void> reorderItineraryItems(
    String tripId,
    List<ItineraryItem> items,
  ) async {
    // TODO(travel-passport): Move itinerary to a subcollection to reduce doc contention.
    if (items.isEmpty) return;
    final docRef = _trips.doc(tripId);
    await firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      final trip = _deserializeTrip(snapshot);
      if (trip == null) return;
      final updatesById = {for (final item in items) item.id: item};
      final updatedItinerary = trip.itinerary.map((item) {
        return updatesById[item.id] ?? item;
      }).toList();
      final updatedTrip = trip.copyWith(
        itinerary: updatedItinerary,
        updatedAt: DateTime.now(),
      );
      final update = _buildUpdate(
        text: 'Reordered the itinerary for the day.',
        kind: TripUpdateKind.planner,
      );
      transaction.set(docRef, _serializeTrip(_withUpdate(updatedTrip, update)));
    });
  }

  @override
  Future<List<ItineraryItem>> getItinerary(
    String tripId, {
    DateTime? day,
  }) async {
    final trip = await getTripById(tripId);
    if (trip == null) return [];
    if (day == null) return trip.itinerary;
    return trip.getItemsForDay(trip.startDate.difference(day).inDays);
  }

  @override
  Future<Invite> createInvite({
    required String tripId,
    String? invitedEmail,
  }) async {
    final now = DateTime.now();
    final invite = Invite(
      id: _invites.doc().id,
      tripId: tripId,
      token: const Uuid().v4(),
      invitedEmail: invitedEmail,
      createdBy: currentUserId,
      createdAt: now,
      expiresAt: now.add(const Duration(days: 30)),
    );
    await _invites.doc(invite.id).set(invite.toFirestore());
    return invite;
  }

  @override
  Future<Invite?> getInviteByToken(String token) async {
    final snapshot = await _invites
        .where('token', isEqualTo: token)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return null;
    return Invite.fromFirestore(snapshot.docs.first.data());
  }

  @override
  Future<void> markInviteAsUsed(String inviteId) async {
    await _invites.doc(inviteId).update({'isUsed': true});
  }

  @override
  Future<void> publishTrip(String tripId, bool isPublished) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    await _saveTrip(
      trip.copyWith(isPublished: isPublished, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> publishToWall(String tripId, bool publish) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    // TODO(travel-passport): Move story publishing state to a story subcollection.
    final updated = trip.copyWith(
      story: trip.story.copyWith(publishToWall: publish),
      updatedAt: DateTime.now(),
    );
    final update = _buildUpdate(
      text: publish
          ? 'Published the story to the wall.'
          : 'Removed the story from the wall.',
      kind: TripUpdateKind.story,
    );
    await _saveTrip(_withUpdate(updated, update));
  }

  @override
  Future<void> likeTrip(String tripId) async {
    await setTripLike(tripId, true);
    // TODO(travel-passport): Move wall stats to a story subcollection.
  }

  @override
  Future<void> setTripLike(String tripId, bool liked) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final wasLiked = trip.story.likedBy.contains(currentUserId);
    final updatedLikedBy = [...trip.story.likedBy];
    if (liked && !wasLiked) {
      updatedLikedBy.add(currentUserId);
    } else if (!liked && wasLiked) {
      updatedLikedBy.remove(currentUserId);
    }
    var likes = trip.story.wallStats.likes;
    if (liked && !wasLiked) likes += 1;
    if (!liked && wasLiked) likes -= 1;
    if (likes < 0) likes = 0;
    final stats = trip.story.wallStats.copyWith(likes: likes);
    await _saveTrip(
      trip.copyWith(
        story: trip.story.copyWith(likedBy: updatedLikedBy, wallStats: stats),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> addWallComment(String tripId, WallComment comment) async {
    // TODO(travel-passport): Move wall comments to a subcollection.
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedComments = [...trip.story.wallComments, comment];
    final stats = trip.story.wallStats.copyWith(
      comments: trip.story.wallStats.comments + 1,
    );
    await _saveTrip(
      trip.copyWith(
        story: trip.story.copyWith(
          wallComments: updatedComments,
          wallStats: stats,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> sendChatMessage(String tripId, ChatMessage message) async {
    // TODO(travel-passport): Move chat to a subcollection.
    final trip = await getTripById(tripId);
    if (trip == null) return;
    await _saveTrip(
      trip.copyWith(chat: [...trip.chat, message], updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> updateMemberChecklist(
    String tripId,
    MemberChecklist checklist,
  ) async {
    // TODO(travel-passport): Move checklists to a subcollection.
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedChecklist = _upsertMemberChecklist(trip.checklist, checklist);
    await _saveTrip(
      trip.copyWith(checklist: updatedChecklist, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> upsertSharedChecklistItem(
    String tripId,
    ChecklistItem item,
  ) async {
    // TODO(travel-passport): Move checklists to a subcollection.
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final existingIndex = trip.checklist.shared.indexWhere(
      (s) => s.id == item.id,
    );
    final updatedShared = [...trip.checklist.shared];
    if (existingIndex >= 0) {
      updatedShared[existingIndex] = item;
    } else {
      updatedShared.add(item);
    }
    await _saveTrip(
      trip.copyWith(
        checklist: trip.checklist.copyWith(shared: updatedShared),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> deleteSharedChecklistItem(String tripId, String itemId) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedShared = trip.checklist.shared
        .where((s) => s.id != itemId)
        .toList();
    await _saveTrip(
      trip.copyWith(
        checklist: trip.checklist.copyWith(shared: updatedShared),
        updatedAt: DateTime.now(),
      ),
    );
  }

  TripChecklist _upsertMemberChecklist(
    TripChecklist checklist,
    MemberChecklist entry,
  ) {
    final existingIndex = checklist.members.indexWhere(
      (m) => m.userId == entry.userId,
    );
    final updated = [...checklist.members];
    if (existingIndex >= 0) {
      updated[existingIndex] = entry;
    } else {
      updated.add(entry);
    }
    return checklist.copyWith(members: updated);
  }

  @override
  Future<void> requestToJoin(String tripId, JoinRequest request) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    await _saveTrip(
      trip.copyWith(
        joinRequests: [request, ...trip.joinRequests],
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> respondToJoinRequest(
    String tripId,
    String requestId,
    JoinRequestStatus status,
  ) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedRequests = trip.joinRequests.map((request) {
      if (request.id != requestId) return request;
      return request.copyWith(status: status);
    }).toList();

    var updatedMembers = trip.members;
    if (status == JoinRequestStatus.approved) {
      final req = updatedRequests.firstWhere((r) => r.id == requestId);
      final exists = updatedMembers.any((m) => m.userId == req.userId);
      if (!exists) {
        updatedMembers = [
          ...updatedMembers,
          Member(
            userId: req.userId,
            name: 'Guest Traveler',
            role: MemberRole.viewer,
            joinedAt: DateTime.now(),
          ),
        ];
      }
    }

    await _saveTrip(
      trip.copyWith(
        joinRequests: updatedRequests,
        members: updatedMembers,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Stream<List<Trip>> watchUserTrips() {
    return _trips
        .where('memberIds', arrayContains: currentUserId)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map(_deserializeTrip).whereType<Trip>().toList()
                ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)),
        );
  }

  @override
  Stream<Trip?> watchTrip(String tripId) {
    return _trips.doc(tripId).snapshots().map(_deserializeTrip);
  }

  @override
  Stream<List<ItineraryItem>> watchItinerary(String tripId) {
    return watchTrip(tripId).map((trip) => trip?.itinerary ?? []);
  }

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    final doc = await _users.doc(userId).get();
    if (!doc.exists) return null;
    final data = doc.data();
    if (data == null) return null;
    return UserProfile.fromFirestore(data);
  }

  @override
  Future<void> updateUserProfile(UserProfile profile) async {
    await _users.doc(profile.userId).set(profile.toFirestore());
  }
}
