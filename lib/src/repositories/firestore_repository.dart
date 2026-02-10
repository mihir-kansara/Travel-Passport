import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
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

  CollectionReference<Map<String, dynamic>> _itineraryCollection(String tripId) {
    return _trips.doc(tripId).collection('itinerary');
  }

  CollectionReference<Map<String, dynamic>> _messagesCollection(String tripId) {
    return _trips.doc(tripId).collection('messages');
  }

  CollectionReference<Map<String, dynamic>> _commentsCollection(String tripId) {
    return _trips.doc(tripId).collection('comments');
  }

  CollectionReference<Map<String, dynamic>> _itineraryCommentsCollection(
    String tripId,
    String itemId,
  ) {
    return _itineraryCollection(tripId).doc(itemId).collection('comments');
  }

  String _dayKey(DateTime dateTime) {
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day';
  }

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
    final data = {...trip.toJson()};
    data.remove('itinerary');
    data.remove('chat');
    final story = Map<String, dynamic>.from(data['story'] as Map? ?? {});
    story.remove('wallComments');
    data['story'] = story;
    return {
      ...data,
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

  Map<String, dynamic> _itineraryDocData(
    ItineraryItem item, {
    bool preserveTimestamps = false,
  }) {
    return {
      'id': item.id,
      'tripId': item.tripId,
      'dateTime': item.dateTime,
      'dayKey': _dayKey(item.dateTime),
      'title': item.title,
      'description': item.description,
      'notes': item.notes,
      'type': item.type.name,
      'location': item.location,
      'imageUrl': item.imageUrl,
      'assignedTo': item.assignedTo,
      'assigneeId': item.assigneeId,
      'assigneeName': item.assigneeName,
      'link': item.link,
      'isCompleted': item.isCompleted,
      'status': item.status.name,
      'manualOrder': item.order,
      'order': item.order,
      'createdAt': preserveTimestamps
          ? Timestamp.fromDate(item.createdAt)
          : FieldValue.serverTimestamp(),
      'updatedAt': preserveTimestamps
          ? Timestamp.fromDate(item.updatedAt)
          : FieldValue.serverTimestamp(),
      'createdAtClient': item.createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _chatDocData(
    ChatMessage message, {
    bool preserveTimestamps = false,
  }) {
    return {
      'id': message.id,
      'authorId': message.authorId,
      'text': message.text,
      'createdAt': preserveTimestamps
          ? Timestamp.fromDate(message.createdAt)
          : FieldValue.serverTimestamp(),
      'updatedAt': preserveTimestamps
          ? Timestamp.fromDate(message.createdAt)
          : FieldValue.serverTimestamp(),
      'createdAtClient': message.createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _commentDocData(
    WallComment comment, {
    bool preserveTimestamps = false,
  }) {
    return {
      'id': comment.id,
      'authorId': comment.authorId,
      'text': comment.text,
      'createdAt': preserveTimestamps
          ? Timestamp.fromDate(comment.createdAt)
          : FieldValue.serverTimestamp(),
      'updatedAt': preserveTimestamps
          ? Timestamp.fromDate(comment.createdAt)
          : FieldValue.serverTimestamp(),
      'createdAtClient': comment.createdAt.toIso8601String(),
    };
  }

  Map<String, dynamic> _itineraryCommentDocData(
    ItineraryComment comment, {
    bool preserveTimestamps = false,
  }) {
    return {
      'id': comment.id,
      'authorId': comment.authorId,
      'text': comment.text,
      'createdAt': preserveTimestamps
          ? Timestamp.fromDate(comment.createdAt)
          : FieldValue.serverTimestamp(),
      'updatedAt': preserveTimestamps
          ? Timestamp.fromDate(comment.createdAt)
          : FieldValue.serverTimestamp(),
      'createdAtClient': comment.createdAt.toIso8601String(),
    };
  }

  Future<void> _migrateItineraryIfNeeded(
    String tripId,
    List<ItineraryItem> legacyItems,
  ) async {
    if (legacyItems.isEmpty) return;
    final existing = await _itineraryCollection(tripId).limit(1).get();
    if (existing.docs.isNotEmpty) return;
    final batch = firestore.batch();
    final collection = _itineraryCollection(tripId);
    for (final item in legacyItems) {
      batch.set(collection.doc(item.id), _itineraryDocData(
        item,
        preserveTimestamps: true,
      ));
    }
    batch.update(_trips.doc(tripId), {
      'itinerary': [],
      'migrations.itinerary': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> _migrateChatIfNeeded(
    String tripId,
    List<ChatMessage> legacyMessages,
  ) async {
    if (legacyMessages.isEmpty) return;
    final existing = await _messagesCollection(tripId).limit(1).get();
    if (existing.docs.isNotEmpty) return;
    final batch = firestore.batch();
    final collection = _messagesCollection(tripId);
    for (final message in legacyMessages) {
      batch.set(collection.doc(message.id), _chatDocData(
        message,
        preserveTimestamps: true,
      ));
    }
    batch.update(_trips.doc(tripId), {
      'chat': [],
      'migrations.chat': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  Future<void> _migrateWallCommentsIfNeeded(
    String tripId,
    List<WallComment> legacyComments,
  ) async {
    if (legacyComments.isEmpty) return;
    final existing = await _commentsCollection(tripId).limit(1).get();
    if (existing.docs.isNotEmpty) return;
    final batch = firestore.batch();
    final collection = _commentsCollection(tripId);
    for (final comment in legacyComments) {
      batch.set(collection.doc(comment.id), _commentDocData(
        comment,
        preserveTimestamps: true,
      ));
    }
    batch.update(_trips.doc(tripId), {
      'story.wallComments': [],
      'migrations.tripComments': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
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
    final profile = await getUserProfile(currentUserId);
    final ownerName = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : 'Traveler';
    final ownerPhotoUrl = profile?.photoUrl;
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
          name: ownerName,
          avatarUrl: ownerPhotoUrl,
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
    final itemRef = _itineraryCollection(tripId).doc(item.id);
    final existing = await itemRef.get();
    var nextItem = item;
    if (!existing.exists) {
      final nextOrder = await _nextOrderForDayInCollection(
        tripId,
        item.dateTime,
      );
      nextItem = item.copyWith(order: nextOrder);
    }
    await itemRef.set(_itineraryDocData(nextItem), SetOptions(merge: true));
    await _trips.doc(tripId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return nextItem;
  }

  Future<int> _nextOrderForDayInCollection(
    String tripId,
    DateTime dateTime,
  ) async {
    final snapshot = await _itineraryCollection(tripId)
        .where('dayKey', isEqualTo: _dayKey(dateTime))
        .orderBy('manualOrder', descending: true)
        .limit(1)
        .get();
    if (snapshot.docs.isEmpty) return 0;
    final data = snapshot.docs.first.data();
    final current = (data['manualOrder'] ?? data['order'] ?? 0) as int;
    return current + 1;
  }

  @override
  Future<void> deleteItineraryItem(String tripId, String itemId) async {
    await _itineraryCollection(tripId).doc(itemId).delete();
    await _trips.doc(tripId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> reorderItineraryItems(
    String tripId,
    List<ItineraryItem> items,
  ) async {
    if (items.isEmpty) return;
    final batch = firestore.batch();
    final collection = _itineraryCollection(tripId);
    for (final item in items) {
      batch.update(collection.doc(item.id), {
        'manualOrder': item.order,
        'order': item.order,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    batch.update(_trips.doc(tripId), {
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  @override
  Future<List<ItineraryItem>> getItinerary(
    String tripId, {
    DateTime? day,
  }) async {
    var query = _itineraryCollection(tripId)
        .orderBy('dayKey')
        .orderBy('manualOrder')
        .orderBy('dateTime');
    if (day != null) {
      query = query.where('dayKey', isEqualTo: _dayKey(day));
    }
    final snapshot = await query.get();
    final items = snapshot.docs
        .map((doc) => ItineraryItem.fromFirestore(doc.data()))
        .toList();
    if (items.isNotEmpty) return items;
    final trip = await getTripById(tripId);
    if (trip == null) return [];
    await _migrateItineraryIfNeeded(tripId, trip.itinerary);
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
    await _commentsCollection(tripId)
        .doc(comment.id)
        .set(_commentDocData(comment));
    await _trips.doc(tripId).set({
      'story': {
        'wallStats': {'comments': FieldValue.increment(1)},
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> sendChatMessage(String tripId, ChatMessage message) async {
    await _messagesCollection(tripId)
        .doc(message.id)
        .set(_chatDocData(message));
    await _trips.doc(tripId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
        final profile = await getUserProfile(req.userId);
        final displayName = profile?.displayName.isNotEmpty == true
            ? profile!.displayName
            : 'Traveler';
        updatedMembers = [
          ...updatedMembers,
          Member(
            userId: req.userId,
            name: displayName,
            avatarUrl: profile?.photoUrl,
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
    final subStream = _itineraryCollection(tripId)
        .orderBy('dayKey')
        .orderBy('manualOrder')
        .orderBy('dateTime')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) {
                return ItineraryItem.fromFirestore(doc.data());
              }).toList(),
        );
    final legacyStream = watchTrip(tripId).asyncMap((trip) async {
      final legacyItems = trip?.itinerary ?? [];
      await _migrateItineraryIfNeeded(tripId, legacyItems);
      return legacyItems;
    });
    return Rx.combineLatest2<List<ItineraryItem>, List<ItineraryItem>,
        List<ItineraryItem>>(
      subStream,
      legacyStream,
      (subItems, legacyItems) =>
          subItems.isNotEmpty ? subItems : legacyItems,
    );
  }

  @override
  Stream<List<WallComment>> watchTripComments(String tripId, {int limit = 100}) {
    final subStream = _commentsCollection(tripId)
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) {
                return WallComment.fromJson(doc.data());
              }).toList(),
        );
    final legacyStream = watchTrip(tripId).asyncMap((trip) async {
      final legacy = trip?.story.wallComments ?? [];
      await _migrateWallCommentsIfNeeded(tripId, legacy);
      return legacy;
    });
    return Rx.combineLatest2<List<WallComment>, List<WallComment>,
        List<WallComment>>(
      subStream,
      legacyStream,
      (subItems, legacyItems) =>
          subItems.isNotEmpty ? subItems : legacyItems,
    );
  }

  @override
  Stream<List<ChatMessage>> watchChatMessages(
    String tripId, {
    int limit = 50,
  }) {
    final subStream = _messagesCollection(tripId)
        .orderBy('createdAt', descending: true)
        .orderBy('id', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          final messages = snapshot.docs
              .map((doc) => ChatMessage.fromJson(doc.data()))
              .toList();
          messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
          return messages;
        });
    final legacyStream = watchTrip(tripId).asyncMap((trip) async {
      final legacy = trip?.chat ?? [];
      await _migrateChatIfNeeded(tripId, legacy);
      return legacy;
    });
    return Rx.combineLatest2<List<ChatMessage>, List<ChatMessage>,
        List<ChatMessage>>(
      subStream,
      legacyStream,
      (subItems, legacyItems) =>
          subItems.isNotEmpty ? subItems : legacyItems,
    );
  }

  @override
  Future<List<ChatMessage>> fetchChatMessagesPage(
    String tripId, {
    int limit = 50,
    ChatMessagesCursor? before,
  }) async {
    var query = _messagesCollection(tripId)
        .orderBy('createdAt', descending: true)
        .orderBy('id', descending: true)
        .limit(limit);
    if (before != null) {
      query = query.startAfter([
        Timestamp.fromDate(before.createdAt),
        before.messageId,
      ]);
    }
    final snapshot = await query.get();
    final messages = snapshot.docs
        .map((doc) => ChatMessage.fromJson(doc.data()))
        .toList();
    messages.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return messages;
  }

  @override
  Stream<List<ItineraryComment>> watchItineraryComments(
    String tripId,
    String itemId,
  ) {
    return _itineraryCommentsCollection(tripId, itemId)
        .orderBy('createdAt')
        .snapshots()
        .map(
          (snapshot) =>
              snapshot.docs.map((doc) {
                return ItineraryComment.fromJson(doc.data());
              }).toList(),
        );
  }

  @override
  Future<void> addItineraryComment(
    String tripId,
    String itemId,
    ItineraryComment comment,
  ) async {
    await _itineraryCommentsCollection(tripId, itemId)
        .doc(comment.id)
        .set(_itineraryCommentDocData(comment));
    await _itineraryCollection(tripId).doc(itemId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
    await _users
        .doc(profile.userId)
        .set(profile.toFirestore(), SetOptions(merge: true));
  }
}
