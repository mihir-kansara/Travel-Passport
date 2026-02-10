import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/models/friends.dart';
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
  CollectionReference<Map<String, dynamic>> get _friendRequests =>
      firestore.collection('friend_requests');
  CollectionReference<Map<String, dynamic>> get _friendships =>
      firestore.collection('friendships');
  CollectionReference<Map<String, dynamic>> get _blocks =>
      firestore.collection('blocks');
  CollectionReference<Map<String, dynamic>> get _itineraryCategories =>
      firestore.collection('itinerary_categories');

  final BehaviorSubject<List<_PendingItineraryOp>> _pendingOps =
      BehaviorSubject.seeded(const []);
  bool _pendingLoaded = false;

  CollectionReference<Map<String, dynamic>> _itineraryCollection(
    String tripId,
  ) {
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

  String _pairKey(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids.first}_${ids.last}';
  }

  int _sectionOrder(ItinerarySection section) {
    switch (section) {
      case ItinerarySection.morning:
        return 0;
      case ItinerarySection.afternoon:
        return 1;
      case ItinerarySection.evening:
        return 2;
    }
  }

  List<ItineraryItem> _sortedItineraryItems(List<ItineraryItem> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      final dayCompare = _dayKey(a.dateTime).compareTo(_dayKey(b.dateTime));
      if (dayCompare != 0) return dayCompare;
      final sectionCompare = _sectionOrder(
        a.section,
      ).compareTo(_sectionOrder(b.section));
      if (sectionCompare != 0) return sectionCompare;
      final orderCompare = a.order.compareTo(b.order);
      if (orderCompare != 0) return orderCompare;
      if (a.isTimeSet != b.isTimeSet) {
        return a.isTimeSet ? -1 : 1;
      }
      final timeCompare = a.dateTime.compareTo(b.dateTime);
      if (timeCompare != 0) return timeCompare;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  List<ChatMessage> _sortedChatMessages(List<ChatMessage> messages) {
    final sorted = [...messages];
    sorted.sort((a, b) {
      final timeCompare = a.createdAt.compareTo(b.createdAt);
      if (timeCompare != 0) return timeCompare;
      return a.id.compareTo(b.id);
    });
    return sorted;
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
      'section': item.section.name,
      'isTimeSet': item.isTimeSet,
      'categoryId': item.categoryId,
      'location': item.location,
      'imageUrl': item.imageUrl,
      'photoUrls': item.photoUrls,
      'cost': item.cost,
      'tags': item.tags,
      'assignedTo': item.assignedTo,
      'assigneeId': item.assigneeId,
      'assigneeName': item.assigneeName,
      'link': item.link,
      'createdBy': item.createdBy,
      'updatedBy': item.updatedBy,
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

  Future<void> _ensurePendingLoaded() async {
    if (_pendingLoaded) return;
    _pendingLoaded = true;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_PendingItineraryOp.storageKey);
    if (raw == null || raw.isEmpty) return;
    final decoded = jsonDecode(raw);
    if (decoded is! List) return;
    final ops = decoded
        .whereType<Map<String, dynamic>>()
        .map(_PendingItineraryOp.fromJson)
        .toList();
    _pendingOps.add(ops);
  }

  Future<void> _persistPendingOps() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = jsonEncode(
      _pendingOps.value.map((op) => op.toJson()).toList(),
    );
    await prefs.setString(_PendingItineraryOp.storageKey, payload);
  }

  Future<void> _enqueuePending(_PendingItineraryOp op) async {
    await _ensurePendingLoaded();
    final updated = [..._pendingOps.value, op];
    _pendingOps.add(updated);
    await _persistPendingOps();
  }

  Future<void> _flushPendingOps() async {
    await _ensurePendingLoaded();
    final pending = [..._pendingOps.value];
    if (pending.isEmpty) return;
    final remaining = <_PendingItineraryOp>[];
    for (final op in pending) {
      try {
        await _applyPendingOp(op);
      } catch (_) {
        remaining.add(op);
        break;
      }
    }
    if (remaining.length != pending.length) {
      _pendingOps.add(remaining);
      await _persistPendingOps();
    }
  }

  List<ItineraryItem> _applyPendingOpsToItems(
    List<ItineraryItem> base,
    List<_PendingItineraryOp> ops,
  ) {
    if (ops.isEmpty) return base;
    final items = [...base];
    for (final op in ops) {
      switch (op.type) {
        case _PendingItineraryOpType.upsert:
          final data = op.payload['item'];
          if (data is Map<String, dynamic>) {
            final item = ItineraryItem.fromFirestore(data);
            final existingIndex = items.indexWhere(
              (entry) => entry.id == item.id,
            );
            if (existingIndex >= 0) {
              items[existingIndex] = item;
            } else {
              items.add(item);
            }
          }
        case _PendingItineraryOpType.delete:
          final itemId = op.payload['itemId'] as String?;
          if (itemId != null) {
            items.removeWhere((entry) => entry.id == itemId);
          }
        case _PendingItineraryOpType.reorder:
          final updates = op.payload['orders'];
          if (updates is List) {
            for (final entry in updates) {
              if (entry is! Map<String, dynamic>) continue;
              final itemId = entry['id'] as String?;
              final order = entry['order'] as int?;
              if (itemId == null || order == null) continue;
              final index = items.indexWhere((item) => item.id == itemId);
              if (index >= 0) {
                items[index] = items[index].copyWith(
                  order: order,
                  updatedAt: DateTime.now(),
                );
              }
            }
          }
        case _PendingItineraryOpType.addComment:
          break;
      }
    }
    return _sortedItineraryItems(items);
  }

  Future<void> _applyPendingOp(_PendingItineraryOp op) async {
    switch (op.type) {
      case _PendingItineraryOpType.upsert:
        final data = op.payload['item'];
        if (data is! Map<String, dynamic>) return;
        final item = ItineraryItem.fromFirestore(data);
        final itemRef = _itineraryCollection(op.tripId).doc(item.id);
        await itemRef.set(_itineraryDocData(item), SetOptions(merge: true));
        await _appendTripUpdate(
          op.tripId,
          _buildUpdate(
            text: 'Updated ${item.title}.',
            kind: TripUpdateKind.planner,
          ),
        );
      case _PendingItineraryOpType.delete:
        final itemId = op.payload['itemId'] as String?;
        if (itemId == null) return;
        await _itineraryCollection(op.tripId).doc(itemId).delete();
        await _appendTripUpdate(
          op.tripId,
          _buildUpdate(
            text: 'Removed an itinerary item.',
            kind: TripUpdateKind.planner,
          ),
        );
      case _PendingItineraryOpType.reorder:
        final updates = op.payload['orders'];
        if (updates is! List) return;
        final batch = firestore.batch();
        final collection = _itineraryCollection(op.tripId);
        for (final entry in updates) {
          if (entry is! Map<String, dynamic>) continue;
          final itemId = entry['id'] as String?;
          final order = entry['order'] as int?;
          if (itemId == null || order == null) continue;
          batch.update(collection.doc(itemId), {
            'manualOrder': order,
            'order': order,
            'updatedAt': FieldValue.serverTimestamp(),
            'updatedBy': currentUserId,
          });
        }
        await batch.commit();
        await _appendTripUpdate(
          op.tripId,
          _buildUpdate(
            text: 'Reordered the day plan.',
            kind: TripUpdateKind.planner,
          ),
        );
      case _PendingItineraryOpType.addComment:
        final itemId = op.payload['itemId'] as String?;
        final data = op.payload['comment'];
        if (itemId == null || data is! Map<String, dynamic>) return;
        final comment = ItineraryComment.fromJson(data);
        await _itineraryCommentsCollection(
          op.tripId,
          itemId,
        ).doc(comment.id).set(_itineraryCommentDocData(comment));
        await _appendTripUpdate(
          op.tripId,
          _buildUpdate(
            text: 'Added a comment to the itinerary.',
            kind: TripUpdateKind.planner,
          ),
        );
    }
  }

  Future<void> _appendTripUpdate(String tripId, TripUpdate update) async {
    await _trips.doc(tripId).set({
      'updates': FieldValue.arrayUnion([update.toJson()]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Map<String, dynamic> _chatDocData(
    ChatMessage message, {
    bool preserveTimestamps = false,
  }) {
    return {
      'id': message.id,
      'authorId': message.authorId,
      'text': message.text,
      'kind': message.kind.name,
      'mentions': message.mentions,
      'itemRefs': message.itemRefs.map((ref) => ref.toJson()).toList(),
      'replyToMessageId': message.replyToMessageId,
      'reactions': message.reactions,
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

  Future<void> _sendSystemChatMessage(
    String tripId,
    String text, {
    String? actorId,
  }) async {
    final message = ChatMessage(
      id: const Uuid().v4(),
      authorId: actorId ?? currentUserId,
      text: text,
      createdAt: DateTime.now(),
      kind: ChatMessageKind.system,
    );
    await sendChatSystemMessage(tripId, message);
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
      batch.set(
        collection.doc(item.id),
        _itineraryDocData(item, preserveTimestamps: true),
      );
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
      batch.set(
        collection.doc(message.id),
        _chatDocData(message, preserveTimestamps: true),
      );
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
      batch.set(
        collection.doc(comment.id),
        _commentDocData(comment, preserveTimestamps: true),
      );
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
        personalItemsByUserId: {currentUserId: const []},
        personalVisibilityByUserId: {currentUserId: false},
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
    final updatedChecklist = _ensurePersonalChecklist(
      trip.checklist,
      member.userId,
    );
    final update = _buildUpdate(
      actorId: member.userId,
      text: '${member.name} joined the trip.',
      kind: TripUpdateKind.people,
    );
    await _saveTrip(
      _withUpdate(updated.copyWith(checklist: updatedChecklist), update),
    );
    await _sendSystemChatMessage(
      tripId,
      '${member.name} joined the trip.',
      actorId: member.userId,
    );
  }

  @override
  Future<void> removeMember(String tripId, String userId) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final memberName = trip.members
        .firstWhere(
          (m) => m.userId == userId,
          orElse: () => trip.members.first,
        )
        .name;
    final updatedChecklist = _removePersonalChecklist(trip.checklist, userId);
    await _saveTrip(
      trip.copyWith(
        members: trip.members.where((m) => m.userId != userId).toList(),
        checklist: updatedChecklist,
        updatedAt: DateTime.now(),
      ),
    );
    await _sendSystemChatMessage(
      tripId,
      '$memberName left the trip.',
      actorId: userId,
    );
  }

  @override
  Future<void> updateMemberRole(
    String tripId,
    String userId,
    MemberRole role,
  ) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final memberIndex = trip.members.indexWhere((m) => m.userId == userId);
    if (memberIndex < 0) return;
    if (userId == trip.ownerId && role != MemberRole.owner) return;

    var updatedOwnerId = trip.ownerId;
    final updatedMembers = trip.members.map((member) {
      if (member.userId == userId) {
        return member.copyWith(role: role);
      }
      if (role == MemberRole.owner && member.role == MemberRole.owner) {
        return member.copyWith(role: MemberRole.collaborator);
      }
      return member;
    }).toList();

    if (role == MemberRole.owner) {
      updatedOwnerId = userId;
    }

    await _saveTrip(
      trip.copyWith(
        ownerId: updatedOwnerId,
        members: updatedMembers,
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<ItineraryItem> upsertItineraryItem(
    String tripId,
    ItineraryItem item,
  ) async {
    await _flushPendingOps();
    final itemRef = _itineraryCollection(tripId).doc(item.id);
    final existing = await itemRef.get();
    var nextItem = item.copyWith(
      createdBy: item.createdBy ?? currentUserId,
      updatedBy: currentUserId,
      updatedAt: DateTime.now(),
    );
    if (!existing.exists) {
      final nextOrder = await _nextOrderForDayInCollection(
        tripId,
        item.dateTime,
        item.section,
      );
      nextItem = nextItem.copyWith(order: nextOrder);
    }
    try {
      await itemRef.set(_itineraryDocData(nextItem), SetOptions(merge: true));
      await _appendTripUpdate(
        tripId,
        _buildUpdate(
          text: existing.exists
              ? 'Updated ${nextItem.title}.'
              : 'Added ${nextItem.title}.',
          kind: TripUpdateKind.planner,
        ),
      );
      await _sendSystemChatMessage(
        tripId,
        existing.exists
            ? 'Updated itinerary: ${nextItem.title}.'
            : 'Added to itinerary: ${nextItem.title}.',
      );
      return nextItem;
    } catch (e) {
      await _enqueuePending(
        _PendingItineraryOp.upsert(tripId: tripId, item: nextItem),
      );
      return nextItem;
    }
  }

  Future<int> _nextOrderForDayInCollection(
    String tripId,
    DateTime dateTime,
    ItinerarySection section,
  ) async {
    final snapshot = await _itineraryCollection(tripId)
        .where('dayKey', isEqualTo: _dayKey(dateTime))
        .where('section', isEqualTo: section.name)
        .get();
    if (snapshot.docs.isEmpty) return 0;
    var maxOrder = 0;
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final current = (data['manualOrder'] ?? data['order'] ?? 0) as int;
      if (current > maxOrder) {
        maxOrder = current;
      }
    }
    return maxOrder + 1;
  }

  @override
  Future<void> deleteItineraryItem(String tripId, String itemId) async {
    await _flushPendingOps();
    try {
      final existing = await _itineraryCollection(tripId).doc(itemId).get();
      final existingTitle =
          (existing.data()?['title'] as String?) ?? 'an itinerary item';
      await _itineraryCollection(tripId).doc(itemId).delete();
      await _appendTripUpdate(
        tripId,
        _buildUpdate(
          text: 'Removed an itinerary item.',
          kind: TripUpdateKind.planner,
        ),
      );
      await _sendSystemChatMessage(
        tripId,
        'Removed from itinerary: $existingTitle.',
      );
    } catch (e) {
      await _enqueuePending(
        _PendingItineraryOp.delete(tripId: tripId, itemId: itemId),
      );
    }
  }

  @override
  Future<void> reorderItineraryItems(
    String tripId,
    List<ItineraryItem> items,
  ) async {
    if (items.isEmpty) return;
    await _flushPendingOps();
    try {
      final batch = firestore.batch();
      final collection = _itineraryCollection(tripId);
      for (final item in items) {
        batch.update(collection.doc(item.id), {
          'manualOrder': item.order,
          'order': item.order,
          'updatedAt': FieldValue.serverTimestamp(),
          'updatedBy': currentUserId,
        });
      }
      await batch.commit();
      await _appendTripUpdate(
        tripId,
        _buildUpdate(
          text: 'Reordered the day plan.',
          kind: TripUpdateKind.planner,
        ),
      );
      await _sendSystemChatMessage(
        tripId,
        'Updated itinerary order.',
      );
    } catch (e) {
      await _enqueuePending(
        _PendingItineraryOp.reorder(tripId: tripId, items: items),
      );
    }
  }

  @override
  Future<List<ItineraryItem>> getItinerary(
    String tripId, {
    DateTime? day,
  }) async {
    await _ensurePendingLoaded();
    Query<Map<String, dynamic>> query = _itineraryCollection(tripId);
    if (day != null) {
      query = query.where('dayKey', isEqualTo: _dayKey(day));
    }
    final snapshot = await query.get();
    final baseItems = _sortedItineraryItems(
      snapshot.docs
          .map((doc) => ItineraryItem.fromFirestore(doc.data()))
          .toList(),
    );
    final pending = _pendingOps.value
        .where((op) => op.tripId == tripId)
        .toList();
    final items = _applyPendingOpsToItems(baseItems, pending);
    if (items.isNotEmpty) return items;
    final trip = await getTripById(tripId);
    if (trip == null) return [];
    await _migrateItineraryIfNeeded(tripId, trip.itinerary);
    if (day == null) return _sortedItineraryItems(trip.itinerary);
    return _sortedItineraryItems(
      trip.getItemsForDay(day.difference(trip.startDate).inDays),
    );
  }

  @override
  Future<Invite> createInvite({
    required String tripId,
    String? invitedEmail,
    MemberRole role = MemberRole.viewer,
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
      role: role,
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
    await _commentsCollection(
      tripId,
    ).doc(comment.id).set(_commentDocData(comment));
    await _trips.doc(tripId).set({
      'story': {
        'wallStats': {'comments': FieldValue.increment(1)},
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> sendChatMessage(String tripId, ChatMessage message) async {
    await _messagesCollection(
      tripId,
    ).doc(message.id).set(_chatDocData(message));
    await _trips.doc(tripId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> sendChatSystemMessage(String tripId, ChatMessage message) async {
    await _messagesCollection(
      tripId,
    ).doc(message.id).set(_chatDocData(message));
    await _trips.doc(tripId).update({
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> toggleChatReaction(
    String tripId,
    String messageId,
    String emoji,
    bool add,
  ) async {
    final field = 'reactions.$emoji';
    await _messagesCollection(tripId).doc(messageId).set({
      field: add
          ? FieldValue.arrayUnion([currentUserId])
          : FieldValue.arrayRemove([currentUserId]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<void> upsertSharedChecklistItem(
    String tripId,
    ChecklistItem item,
  ) async {
    // TODO(travel-passport): Move checklists to a subcollection.
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final existingIndex = trip.checklist.sharedItems.indexWhere(
      (s) => s.id == item.id,
    );
    final updatedShared = [...trip.checklist.sharedItems];
    if (existingIndex >= 0) {
      updatedShared[existingIndex] = item;
    } else {
      updatedShared.add(item);
    }
    await _saveTrip(
      trip.copyWith(
        checklist: trip.checklist.copyWith(sharedItems: updatedShared),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> deleteSharedChecklistItem(String tripId, String itemId) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedShared = trip.checklist.sharedItems
        .where((s) => s.id != itemId)
        .toList();
    await _saveTrip(
      trip.copyWith(
        checklist: trip.checklist.copyWith(sharedItems: updatedShared),
        updatedAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> upsertPersonalChecklistItem(
    String tripId,
    String ownerUserId,
    ChecklistItem item,
  ) async {
    // TODO(travel-passport): Move checklists to a subcollection.
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedChecklist = _upsertPersonalChecklistItem(
      trip.checklist,
      ownerUserId,
      item,
    );
    await _saveTrip(
      trip.copyWith(checklist: updatedChecklist, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> deletePersonalChecklistItem(
    String tripId,
    String ownerUserId,
    String itemId,
  ) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedChecklist = _deletePersonalChecklistItem(
      trip.checklist,
      ownerUserId,
      itemId,
    );
    await _saveTrip(
      trip.copyWith(checklist: updatedChecklist, updatedAt: DateTime.now()),
    );
  }

  @override
  Future<void> setPersonalChecklistVisibility(
    String tripId,
    String ownerUserId,
    bool isShared,
  ) async {
    final trip = await getTripById(tripId);
    if (trip == null) return;
    final updatedVisibility = Map<String, bool>.from(
      trip.checklist.personalVisibilityByUserId,
    )..[ownerUserId] = isShared;
    await _saveTrip(
      trip.copyWith(
        checklist: trip.checklist.copyWith(
          personalVisibilityByUserId: updatedVisibility,
        ),
        updatedAt: DateTime.now(),
      ),
    );
  }

  TripChecklist _ensurePersonalChecklist(
    TripChecklist checklist,
    String userId,
  ) {
    final updatedItems = Map<String, List<ChecklistItem>>.from(
      checklist.personalItemsByUserId,
    );
    updatedItems.putIfAbsent(userId, () => []);
    final updatedVisibility = Map<String, bool>.from(
      checklist.personalVisibilityByUserId,
    );
    updatedVisibility.putIfAbsent(userId, () => false);
    return checklist.copyWith(
      personalItemsByUserId: updatedItems,
      personalVisibilityByUserId: updatedVisibility,
    );
  }

  TripChecklist _removePersonalChecklist(
    TripChecklist checklist,
    String userId,
  ) {
    final updatedItems = Map<String, List<ChecklistItem>>.from(
      checklist.personalItemsByUserId,
    )..remove(userId);
    final updatedVisibility = Map<String, bool>.from(
      checklist.personalVisibilityByUserId,
    )..remove(userId);
    return checklist.copyWith(
      personalItemsByUserId: updatedItems,
      personalVisibilityByUserId: updatedVisibility,
    );
  }

  TripChecklist _upsertPersonalChecklistItem(
    TripChecklist checklist,
    String ownerUserId,
    ChecklistItem item,
  ) {
    final updatedItems = Map<String, List<ChecklistItem>>.from(
      checklist.personalItemsByUserId,
    );
    final current =
      [...updatedItems[ownerUserId] ?? const <ChecklistItem>[]];
    final existingIndex = current.indexWhere((entry) => entry.id == item.id);
    if (existingIndex >= 0) {
      current[existingIndex] = item;
    } else {
      current.add(item);
    }
    updatedItems[ownerUserId] = current;
    return checklist.copyWith(personalItemsByUserId: updatedItems);
  }

  TripChecklist _deletePersonalChecklistItem(
    TripChecklist checklist,
    String ownerUserId,
    String itemId,
  ) {
    final updatedItems = Map<String, List<ChecklistItem>>.from(
      checklist.personalItemsByUserId,
    );
    final current = [...updatedItems[ownerUserId] ?? const <ChecklistItem>[]]
      ..removeWhere((entry) => entry.id == itemId);
    updatedItems[ownerUserId] = current;
    return checklist.copyWith(personalItemsByUserId: updatedItems);
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
    String? approvedName;
    String? approvedUserId;
    if (status == JoinRequestStatus.approved) {
      final req = updatedRequests.firstWhere((r) => r.id == requestId);
      approvedUserId = req.userId;
      final exists = updatedMembers.any((m) => m.userId == req.userId);
      final profile = await getUserProfile(req.userId);
      final displayName = profile?.displayName.isNotEmpty == true
          ? profile!.displayName
          : 'Traveler';
      approvedName = displayName;
      if (!exists) {
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
      } else {
        updatedMembers = updatedMembers
            .map(
              (member) => member.userId == req.userId
                  ? member.copyWith(role: MemberRole.collaborator)
                  : member,
            )
            .toList();
      }
    }

    await _saveTrip(
      trip.copyWith(
        joinRequests: updatedRequests,
        members: updatedMembers,
        updatedAt: DateTime.now(),
      ),
    );
    if (approvedName != null && approvedUserId != null) {
      await _sendSystemChatMessage(
        tripId,
        '$approvedName joined the trip.',
        actorId: approvedUserId,
      );
    }
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
    _ensurePendingLoaded();
    final subStream = _itineraryCollection(tripId).snapshots().map(
      (snapshot) => _sortedItineraryItems(
        snapshot.docs
            .map((doc) => ItineraryItem.fromFirestore(doc.data()))
            .toList(),
      ),
    );
    final legacyStream = watchTrip(tripId).asyncMap((trip) async {
      final legacyItems = trip?.itinerary ?? [];
      await _migrateItineraryIfNeeded(tripId, legacyItems);
      return legacyItems;
    });
    return Rx.combineLatest3<
      List<ItineraryItem>,
      List<ItineraryItem>,
      List<_PendingItineraryOp>,
      List<ItineraryItem>
    >(subStream, legacyStream, _pendingOps.stream, (
      subItems,
      legacyItems,
      pendingOps,
    ) {
      final base = subItems.isNotEmpty ? subItems : legacyItems;
      final filtered = pendingOps.where((op) => op.tripId == tripId).toList();
      return _applyPendingOpsToItems(base, filtered);
    });
  }

  @override
  Stream<List<WallComment>> watchTripComments(
    String tripId, {
    int limit = 100,
  }) {
    final subStream = _commentsCollection(tripId)
        .orderBy('createdAt')
        .limit(limit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs.map((doc) {
            return WallComment.fromJson(doc.data());
          }).toList(),
        );
    final legacyStream = watchTrip(tripId).asyncMap((trip) async {
      final legacy = trip?.story.wallComments ?? [];
      await _migrateWallCommentsIfNeeded(tripId, legacy);
      return legacy;
    });
    return Rx.combineLatest2<
      List<WallComment>,
      List<WallComment>,
      List<WallComment>
    >(
      subStream,
      legacyStream,
      (subItems, legacyItems) => subItems.isNotEmpty ? subItems : legacyItems,
    );
  }

  @override
  Stream<List<ChatMessage>> watchChatMessages(String tripId, {int limit = 50}) {
    final subStream = _messagesCollection(tripId)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
          return _sortedChatMessages(
            snapshot.docs
                .map((doc) => ChatMessage.fromJson(doc.data()))
                .toList(),
          );
        });
    final legacyStream = watchTrip(tripId).asyncMap((trip) async {
      final legacy = trip?.chat ?? [];
      await _migrateChatIfNeeded(tripId, legacy);
      return legacy;
    });
    return Rx.combineLatest2<
      List<ChatMessage>,
      List<ChatMessage>,
      List<ChatMessage>
    >(
      subStream,
      legacyStream,
      (subItems, legacyItems) => subItems.isNotEmpty ? subItems : legacyItems,
    );
  }

  @override
  Future<List<ChatMessage>> fetchChatMessagesPage(
    String tripId, {
    int limit = 50,
    ChatMessagesCursor? before,
  }) async {
    var query = _messagesCollection(
      tripId,
    ).orderBy('createdAt', descending: true).limit(limit);
    if (before != null) {
      query = query.startAfter([Timestamp.fromDate(before.createdAt)]);
    }
    final snapshot = await query.get();
    return _sortedChatMessages(
      snapshot.docs.map((doc) => ChatMessage.fromJson(doc.data())).toList(),
    );
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
          (snapshot) => snapshot.docs.map((doc) {
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
    await _flushPendingOps();
    try {
      await _itineraryCommentsCollection(
        tripId,
        itemId,
      ).doc(comment.id).set(_itineraryCommentDocData(comment));
      await _appendTripUpdate(
        tripId,
        _buildUpdate(
          text: 'Added a comment to the itinerary.',
          kind: TripUpdateKind.planner,
        ),
      );
    } catch (e) {
      await _enqueuePending(
        _PendingItineraryOp.addComment(
          tripId: tripId,
          itemId: itemId,
          comment: comment,
        ),
      );
    }
  }

  @override
  Future<List<ItineraryCategory>> getItineraryCategories() async {
    final snapshot = await _itineraryCategories.orderBy('order').get();
    final categories = snapshot.docs
        .map((doc) => ItineraryCategory.fromJson(doc.data()))
        .where((entry) => entry.id.isNotEmpty)
        .toList();
    if (categories.isNotEmpty) return categories;
    return _defaultCategories;
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

  @override
  Future<bool> isHandleAvailable(
    String handle, {
    String? excludeUserId,
  }) async {
    final trimmed = handle.trim().toLowerCase();
    if (trimmed.isEmpty) return true;
    final queries = <Future<QuerySnapshot<Map<String, dynamic>>>>[];
    queries.add(_users.where('handle', isEqualTo: trimmed).limit(1).get());
    queries.add(_users.where('username', isEqualTo: trimmed).limit(1).get());
    final snapshots = await Future.wait(queries);
    for (final snapshot in snapshots) {
      if (snapshot.docs.isEmpty) continue;
      final doc = snapshot.docs.first;
      if (excludeUserId != null && doc.id == excludeUserId) {
        continue;
      }
      return false;
    }
    return true;
  }

  @override
  Future<List<UserProfile>> searchUserProfiles(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final isEmail = trimmed.contains('@');
    final isPhone = RegExp(r'^[+\d][\d\s\-()]{5,}$').hasMatch(trimmed);
    final handle = trimmed.startsWith('@') ? trimmed.substring(1) : trimmed;
    final futures = <Future<QuerySnapshot<Map<String, dynamic>>>>[];

    futures.add(
      _users
          .where('displayName', isGreaterThanOrEqualTo: trimmed)
          .where('displayName', isLessThan: '$trimmed\uf8ff')
          .limit(12)
          .get(),
    );
    if (isEmail) {
      futures.add(_users.where('email', isEqualTo: trimmed).limit(1).get());
    }
    if (isPhone) {
      futures.add(_users.where('phone', isEqualTo: trimmed).limit(1).get());
    }
    futures.add(_users.where('handle', isEqualTo: handle).limit(1).get());
    futures.add(_users.where('username', isEqualTo: handle).limit(1).get());

    final snapshots = await Future.wait(futures);
    final profiles = <String, UserProfile>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        final profile = UserProfile.fromFirestore(doc.data());
        if (profile.userId.isEmpty || profile.userId == currentUserId) continue;
        profiles[profile.userId] = profile;
      }
    }
    return profiles.values.toList();
  }

  @override
  Stream<List<Friendship>> watchFriends() {
    return _friendships
        .where('userIds', arrayContains: currentUserId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => Friendship.fromFirestore(doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<FriendRequest>> watchIncomingFriendRequests() {
    return _friendRequests
        .where('toUserId', isEqualTo: currentUserId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FriendRequest.fromFirestore(doc.data()))
              .toList(),
        );
  }

  @override
  Stream<List<FriendRequest>> watchOutgoingFriendRequests() {
    return _friendRequests
        .where('fromUserId', isEqualTo: currentUserId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => FriendRequest.fromFirestore(doc.data()))
              .toList(),
        );
  }

  @override
  Future<void> sendFriendRequest(String toUserId) async {
    if (toUserId.isEmpty || toUserId == currentUserId) return;
    final pairKey = _pairKey(currentUserId, toUserId);
    final friendshipDoc = await _friendships.doc(pairKey).get();
    if (friendshipDoc.exists) return;
    final blockingDoc = await _blocks.doc('${currentUserId}_$toUserId').get();
    if (blockingDoc.exists) return;
    final blockedByDoc = await _blocks.doc('${toUserId}_$currentUserId').get();
    if (blockedByDoc.exists) return;

    final existingOutgoing = await _friendRequests
        .where('fromUserId', isEqualTo: currentUserId)
        .where('toUserId', isEqualTo: toUserId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .limit(1)
        .get();
    if (existingOutgoing.docs.isNotEmpty) return;

    final existingIncoming = await _friendRequests
        .where('fromUserId', isEqualTo: toUserId)
        .where('toUserId', isEqualTo: currentUserId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .limit(1)
        .get();
    if (existingIncoming.docs.isNotEmpty) return;

    final requestId = const Uuid().v4();
    final request = FriendRequest(
      id: requestId,
      fromUserId: currentUserId,
      toUserId: toUserId,
      status: FriendRequestStatus.pending,
      createdAt: DateTime.now(),
    );

    await _friendRequests.doc(requestId).set({
      ...request.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> respondToFriendRequest(
    String requestId,
    FriendRequestStatus status,
  ) async {
    final doc = await _friendRequests.doc(requestId).get();
    if (!doc.exists) return;
    final data = doc.data();
    if (data == null) return;
    final request = FriendRequest.fromFirestore(data);
    if (request.toUserId != currentUserId) return;

    final batch = firestore.batch();
    batch.update(doc.reference, {
      'status': status.name,
      'respondedAt': FieldValue.serverTimestamp(),
    });

    if (status == FriendRequestStatus.accepted) {
      final pairKey = _pairKey(request.fromUserId, request.toUserId);
      final friendship = Friendship(
        id: pairKey,
        userIds: [request.fromUserId, request.toUserId]..sort(),
        createdAt: DateTime.now(),
      );
      batch.set(_friendships.doc(pairKey), {
        ...friendship.toFirestore(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  @override
  Future<void> cancelFriendRequest(String requestId) async {
    final doc = await _friendRequests.doc(requestId).get();
    if (!doc.exists) return;
    final data = doc.data();
    if (data == null) return;
    final request = FriendRequest.fromFirestore(data);
    if (request.fromUserId != currentUserId) return;
    await _friendRequests.doc(requestId).update({
      'status': FriendRequestStatus.canceled.name,
      'respondedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> removeFriend(String friendUserId) async {
    if (friendUserId.isEmpty || friendUserId == currentUserId) return;
    final pairKey = _pairKey(currentUserId, friendUserId);
    await _friendships.doc(pairKey).delete();
  }

  @override
  Future<void> blockUser(String blockedUserId) async {
    if (blockedUserId.isEmpty || blockedUserId == currentUserId) return;
    final blockId = '${currentUserId}_$blockedUserId';
    final batch = firestore.batch();
    batch.set(_blocks.doc(blockId), {
      'id': blockId,
      'blockerId': currentUserId,
      'blockedUserId': blockedUserId,
      'createdAt': FieldValue.serverTimestamp(),
    });

    final pairKey = _pairKey(currentUserId, blockedUserId);
    batch.delete(_friendships.doc(pairKey));

    final outgoing = await _friendRequests
        .where('fromUserId', isEqualTo: currentUserId)
        .where('toUserId', isEqualTo: blockedUserId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .get();
    for (final doc in outgoing.docs) {
      batch.update(doc.reference, {
        'status': FriendRequestStatus.canceled.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });
    }

    final incoming = await _friendRequests
        .where('fromUserId', isEqualTo: blockedUserId)
        .where('toUserId', isEqualTo: currentUserId)
        .where('status', isEqualTo: FriendRequestStatus.pending.name)
        .get();
    for (final doc in incoming.docs) {
      batch.update(doc.reference, {
        'status': FriendRequestStatus.declined.name,
        'respondedAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
  }

  @override
  Future<void> unblockUser(String blockedUserId) async {
    if (blockedUserId.isEmpty || blockedUserId == currentUserId) return;
    final blockId = '${currentUserId}_$blockedUserId';
    await _blocks.doc(blockId).delete();
  }

  @override
  Stream<List<BlockedUser>> watchBlockedUsers() {
    return _blocks
        .where('blockerId', isEqualTo: currentUserId)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map((doc) => BlockedUser.fromFirestore(doc.data()))
              .toList(),
        );
  }
}

const List<ItineraryCategory> _defaultCategories = [
  ItineraryCategory(id: 'flight', label: 'Flight', icon: 'flight', order: 0),
  ItineraryCategory(id: 'lodging', label: 'Lodging', icon: 'hotel', order: 1),
  ItineraryCategory(id: 'food', label: 'Food', icon: 'food', order: 2),
  ItineraryCategory(
    id: 'activity',
    label: 'Activity',
    icon: 'activity',
    order: 3,
  ),
  ItineraryCategory(
    id: 'transport',
    label: 'Transport',
    icon: 'transport',
    order: 4,
  ),
  ItineraryCategory(id: 'note', label: 'Note', icon: 'note', order: 5),
  ItineraryCategory(id: 'other', label: 'Other', icon: 'other', order: 6),
];

enum _PendingItineraryOpType { upsert, delete, reorder, addComment }

class _PendingItineraryOp {
  static const storageKey = 'pending_itinerary_ops';
  final _PendingItineraryOpType type;
  final String tripId;
  final Map<String, dynamic> payload;
  final DateTime createdAt;

  const _PendingItineraryOp({
    required this.type,
    required this.tripId,
    required this.payload,
    required this.createdAt,
  });

  factory _PendingItineraryOp.upsert({
    required String tripId,
    required ItineraryItem item,
  }) {
    return _PendingItineraryOp(
      type: _PendingItineraryOpType.upsert,
      tripId: tripId,
      payload: {'item': item.toFirestore()},
      createdAt: DateTime.now(),
    );
  }

  factory _PendingItineraryOp.delete({
    required String tripId,
    required String itemId,
  }) {
    return _PendingItineraryOp(
      type: _PendingItineraryOpType.delete,
      tripId: tripId,
      payload: {'itemId': itemId},
      createdAt: DateTime.now(),
    );
  }

  factory _PendingItineraryOp.reorder({
    required String tripId,
    required List<ItineraryItem> items,
  }) {
    return _PendingItineraryOp(
      type: _PendingItineraryOpType.reorder,
      tripId: tripId,
      payload: {
        'orders': items
            .map((item) => {'id': item.id, 'order': item.order})
            .toList(),
      },
      createdAt: DateTime.now(),
    );
  }

  factory _PendingItineraryOp.addComment({
    required String tripId,
    required String itemId,
    required ItineraryComment comment,
  }) {
    return _PendingItineraryOp(
      type: _PendingItineraryOpType.addComment,
      tripId: tripId,
      payload: {'itemId': itemId, 'comment': comment.toJson()},
      createdAt: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'type': type.name,
      'tripId': tripId,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory _PendingItineraryOp.fromJson(Map<String, dynamic> data) {
    DateTime parseTimestamp(dynamic value) {
      if (value is DateTime) return value;
      if (value is String && value.isNotEmpty) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return _PendingItineraryOp(
      type: _PendingItineraryOpType.values.firstWhere(
        (entry) => entry.name == (data['type'] as String?),
        orElse: () => _PendingItineraryOpType.upsert,
      ),
      tripId: data['tripId'] as String? ?? '',
      payload: Map<String, dynamic>.from(data['payload'] as Map? ?? {}),
      createdAt: parseTimestamp(data['createdAt']),
    );
  }
}
