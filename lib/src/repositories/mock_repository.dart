import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:uuid/uuid.dart';
import 'package:rxdart/rxdart.dart' show ConcatStream;

/// Mock implementation of TripRepository for development and testing.
class MockTripRepository implements TripRepository {
  final String _currentUserId;
  late List<Trip> _trips;
  final List<Invite> _invites = [];

  MockTripRepository({String currentUserId = 'user_1'})
    : _currentUserId = currentUserId {
    _initMockData();
  }

  TripUpdate _buildUpdate({
    String? actorId,
    required String text,
    required TripUpdateKind kind,
  }) {
    return TripUpdate(
      id: const Uuid().v4(),
      actorId: actorId ?? _currentUserId,
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

  void _initMockData() {
    final now = DateTime.now();
    final currentUser = Member(
      userId: _currentUserId,
      name: 'You',
      role: MemberRole.owner,
      joinedAt: now,
    );

    final collaborator = Member(
      userId: 'user_2',
      name: 'Jane Smith',
      email: 'jane@example.com',
      role: MemberRole.collaborator,
      joinedAt: now.subtract(const Duration(days: 5)),
    );

    final friendA = Member(
      userId: 'user_3',
      name: 'Akshita Rao',
      role: MemberRole.collaborator,
      joinedAt: now.subtract(const Duration(days: 3)),
    );

    final friendB = Member(
      userId: 'user_4',
      name: 'Bhavesh Mehta',
      role: MemberRole.collaborator,
      joinedAt: now.subtract(const Duration(days: 2)),
    );

    _trips = [
      Trip(
        id: 'trip_1',
        ownerId: _currentUserId,
        destination: 'Kyoto, Japan',
        startDate: now.add(const Duration(days: 45)),
        endDate: now.add(const Duration(days: 53)),
        description: 'Calm mornings, temples, and walkable neighborhoods.',
        visibility: TripVisibility.friendsOnly,
        members: [currentUser, collaborator, friendA, friendB],
        itinerary: [
          ItineraryItem(
            id: 'item_1',
            tripId: 'trip_1',
            dateTime: now.add(const Duration(days: 45, hours: 6, minutes: 30)),
            title: 'Fushimi Inari sunrise',
            description: 'Start early to avoid crowds.',
            type: ItineraryItemType.activity,
            location: 'Fushimi Inari Taisha',
            isCompleted: false,
            order: 0,
            createdAt: now,
            updatedAt: now,
          ),
          ItineraryItem(
            id: 'item_2',
            tripId: 'trip_1',
            dateTime: now.add(const Duration(days: 45, hours: 9, minutes: 30)),
            title: 'Coffee',
            description: 'Minimalist cafe, slow morning.',
            type: ItineraryItemType.food,
            location: '% Arabica · Higashiyama',
            isCompleted: false,
            order: 1,
            createdAt: now,
            updatedAt: now,
          ),
          ItineraryItem(
            id: 'item_3',
            tripId: 'trip_1',
            dateTime: now.add(const Duration(days: 46, hours: 12, minutes: 0)),
            title: 'Nishiki Market stroll',
            description: 'Pick snacks and a casual lunch.',
            type: ItineraryItemType.activity,
            location: 'Downtown Kyoto',
            assignedTo: 'user_3',
            isCompleted: false,
            order: 0,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        audience: const TripAudience(
          visibility: TripVisibility.friendsOnly,
          allowJoinRequests: true,
          joinApproval: JoinApproval.owner,
        ),
        updates: [
          TripUpdate(
            id: 'up_1',
            actorId: _currentUserId,
            text: 'Trip created. Invite your people and start planning.',
            kind: TripUpdateKind.system,
            createdAt: now.subtract(const Duration(hours: 3)),
          ),
          TripUpdate(
            id: 'up_2',
            actorId: 'user_2',
            text: 'Added stay options and pinned two cafes.',
            kind: TripUpdateKind.planner,
            createdAt: now.subtract(const Duration(hours: 2, minutes: 20)),
          ),
        ],
        joinRequests: [
          JoinRequest(
            id: 'jr_1',
            userId: 'user_5',
            note: 'I will be around Kyoto, would love to join a day trip.',
            status: JoinRequestStatus.pending,
            createdAt: now.subtract(const Duration(minutes: 40)),
          ),
        ],
        chat: [
          ChatMessage(
            id: 'c_1',
            authorId: 'user_2',
            text: 'I can book the hotel. Any neighborhood preference?',
            createdAt: now.subtract(const Duration(minutes: 50)),
          ),
          ChatMessage(
            id: 'c_2',
            authorId: _currentUserId,
            text: 'Let us optimize for walking and calm mornings. Higashiyama?',
            createdAt: now.subtract(const Duration(minutes: 45)),
          ),
        ],
        story: TripStory(
          headline: 'Calm Kyoto: temples, coffee, and slow mornings.',
          highlights: const [
            'Sunrise at Fushimi Inari',
            'Wood-fired pizza at Monk',
            'Higashiyama walks',
          ],
          photos: const [
            StoryPhoto(
              id: 'ph_1',
              url:
                  'https://images.unsplash.com/photo-1549693578-d683be217e58?auto=format&fit=crop&w=900&q=60',
              caption: 'Fushimi vibes',
            ),
            StoryPhoto(
              id: 'ph_2',
              url:
                  'https://images.unsplash.com/photo-1526481280695-3c687fd5432c?auto=format&fit=crop&w=900&q=60',
              caption: 'Kyoto streets',
            ),
          ],
          moments: [
            StoryMoment(
              id: 'm_1',
              authorId: _currentUserId,
              caption: 'Landing soon. Drop your flight times.',
              createdAt: now.subtract(const Duration(minutes: 65)),
            ),
          ],
          wallStats: const WallStats(likes: 24, comments: 6),
          wallComments: [
            WallComment(
              id: 'wc_1',
              authorId: 'user_6',
              text: 'Kyoto is magic. Following.',
              createdAt: now.subtract(const Duration(minutes: 62)),
            ),
          ],
          publishToWall: true,
          isLive: true,
          isArchived: false,
        ),
        createdAt: now.subtract(const Duration(days: 10)),
        updatedAt: now.subtract(const Duration(days: 2)),
        isPublished: true,
        heroImageUrl:
            'https://images.unsplash.com/photo-1549693578-d683be217e58?auto=format&fit=crop&w=900&q=60',
      ),
      Trip(
        id: 'trip_2',
        ownerId: _currentUserId,
        destination: 'Tulum, Mexico',
        startDate: now.subtract(const Duration(days: 25)),
        endDate: now.subtract(const Duration(days: 19)),
        description: 'Beach days, tacos, no agenda.',
        visibility: TripVisibility.friendsOnly,
        members: [currentUser, collaborator],
        itinerary: [],
        audience: const TripAudience(
          visibility: TripVisibility.friendsOnly,
          allowJoinRequests: false,
          joinApproval: JoinApproval.owner,
        ),
        updates: [
          TripUpdate(
            id: 'up_3',
            actorId: _currentUserId,
            text: 'Trip archived. Share the recap with friends.',
            kind: TripUpdateKind.system,
            createdAt: now.subtract(const Duration(days: 10)),
          ),
        ],
        joinRequests: const [],
        chat: const [],
        story: TripStory(
          headline: 'Beach days + tacos + no agenda.',
          highlights: const ['Cenote swim', 'Sunset dinner', 'Beach club day'],
          photos: const [],
          moments: const [],
          wallStats: const WallStats(likes: 81, comments: 14),
          wallComments: const [],
          publishToWall: true,
          isLive: false,
          isArchived: true,
        ),
        createdAt: now.subtract(const Duration(days: 30)),
        updatedAt: now.subtract(const Duration(days: 2)),
        isPublished: true,
        heroImageUrl:
            'https://images.unsplash.com/photo-1507525428034-b723cf961d3e?w=900',
      ),
    ];
  }

  @override
  Future<List<Trip>> fetchUserTrips() async {
    await Future.delayed(const Duration(milliseconds: 500));
    return _trips
        .where((t) => t.members.any((m) => m.userId == _currentUserId))
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  @override
  Future<Trip?> getTripById(String tripId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      return _trips.firstWhere((t) => t.id == tripId);
    } catch (e) {
      return null;
    }
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
    await Future.delayed(const Duration(milliseconds: 300));
    final now = DateTime.now();
    final update = _buildUpdate(
      text: 'Trip created. Invite your people and start planning.',
      kind: TripUpdateKind.system,
    );
    final trip = Trip(
      id: const Uuid().v4(),
      ownerId: _currentUserId,
      destination: destination,
      startDate: startDate,
      endDate: endDate,
      description: description,
      visibility: visibility,
      audience: TripAudience(visibility: visibility),
      members: [
        Member(
          userId: _currentUserId,
          name: 'You',
          role: MemberRole.owner,
          joinedAt: now,
        ),
      ],
      itinerary: [],
      checklist: TripChecklist(
        members: [MemberChecklist(userId: _currentUserId, updatedAt: now)],
      ),
      updates: [update],
      createdAt: now,
      updatedAt: now,
      heroImageUrl: heroImageUrl,
      coverGradientId: coverGradientId,
    );
    _trips.add(trip);
    return trip;
  }

  @override
  Future<Trip> updateTrip(Trip trip) async {
    await Future.delayed(const Duration(milliseconds: 300));
    final index = _trips.indexWhere((t) => t.id == trip.id);
    if (index >= 0) {
      _trips[index] = trip.copyWith(updatedAt: DateTime.now());
      return _trips[index];
    }
    return trip;
  }

  @override
  Future<void> deleteTrip(String tripId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    _trips.removeWhere((t) => t.id == tripId);
  }

  @override
  Future<void> publishToWall(String tripId, bool publish) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
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
    _trips[_trips.indexOf(trip)] = _withUpdate(updated, update);
  }

  @override
  Future<void> likeTrip(String tripId) async {
    await setTripLike(tripId, true);
  }

  @override
  Future<void> setTripLike(String tripId, bool liked) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final wasLiked = trip.story.likedBy.contains(_currentUserId);
    final updatedLikedBy = [...trip.story.likedBy];
    if (liked && !wasLiked) {
      updatedLikedBy.add(_currentUserId);
    } else if (!liked && wasLiked) {
      updatedLikedBy.remove(_currentUserId);
    }
    var likes = trip.story.wallStats.likes;
    if (liked && !wasLiked) likes += 1;
    if (!liked && wasLiked) likes -= 1;
    if (likes < 0) likes = 0;
    final stats = trip.story.wallStats.copyWith(likes: likes);
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      story: trip.story.copyWith(likedBy: updatedLikedBy, wallStats: stats),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> addWallComment(String tripId, WallComment comment) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updatedComments = [...trip.story.wallComments, comment];
    final stats = trip.story.wallStats.copyWith(
      comments: trip.story.wallStats.comments + 1,
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      story: trip.story.copyWith(
        wallComments: updatedComments,
        wallStats: stats,
      ),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> sendChatMessage(String tripId, ChatMessage message) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      chat: [...trip.chat, message],
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> requestToJoin(String tripId, JoinRequest request) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      joinRequests: [request, ...trip.joinRequests],
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> respondToJoinRequest(
    String tripId,
    String requestId,
    JoinRequestStatus status,
  ) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
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

    _trips[_trips.indexOf(trip)] = trip.copyWith(
      joinRequests: updatedRequests,
      members: updatedMembers,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> addMember(String tripId, Member member) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final memberExists = trip.members.any((m) => m.userId == member.userId);
    if (!memberExists) {
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
      _trips[_trips.indexOf(trip)] = _withUpdate(
        updated.copyWith(checklist: updatedChecklist),
        update,
      );
    }
  }

  @override
  Future<void> removeMember(String tripId, String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updatedChecklist = trip.checklist.copyWith(
      members: trip.checklist.members.where((m) => m.userId != userId).toList(),
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      members: trip.members.where((m) => m.userId != userId).toList(),
      checklist: updatedChecklist,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> updateMemberChecklist(
    String tripId,
    MemberChecklist checklist,
  ) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updatedChecklist = _upsertMemberChecklist(trip.checklist, checklist);
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: updatedChecklist,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> upsertSharedChecklistItem(
    String tripId,
    ChecklistItem item,
  ) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final existingIndex = trip.checklist.shared.indexWhere(
      (s) => s.id == item.id,
    );
    final updatedShared = [...trip.checklist.shared];
    if (existingIndex >= 0) {
      updatedShared[existingIndex] = item;
    } else {
      updatedShared.add(item);
    }
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: trip.checklist.copyWith(shared: updatedShared),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deleteSharedChecklistItem(String tripId, String itemId) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updatedShared = trip.checklist.shared
        .where((s) => s.id != itemId)
        .toList();
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: trip.checklist.copyWith(shared: updatedShared),
      updatedAt: DateTime.now(),
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
  Future<ItineraryItem> upsertItineraryItem(
    String tripId,
    ItineraryItem item,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final existingIndex = trip.itinerary.indexWhere((i) => i.id == item.id);
    final existingItem = existingIndex >= 0
        ? trip.itinerary[existingIndex]
        : null;
    List<ItineraryItem> updatedItinerary;
    String updateText;

    if (existingIndex >= 0) {
      updatedItinerary = [...trip.itinerary];
      updatedItinerary[existingIndex] = item;
      if (existingItem != null &&
          existingItem.isCompleted != item.isCompleted) {
        updateText = item.isCompleted
            ? 'Completed: ${item.title}.'
            : 'Reopened: ${item.title}.';
      } else {
        updateText = 'Updated ${item.type.name}: ${item.title}.';
      }
    } else {
      updatedItinerary = [...trip.itinerary, item];
      updateText = 'Added ${item.type.name}: ${item.title}.';
    }

    final updated = trip.copyWith(
      itinerary: updatedItinerary,
      updatedAt: DateTime.now(),
    );
    final update = _buildUpdate(text: updateText, kind: TripUpdateKind.planner);
    _trips[_trips.indexOf(trip)] = _withUpdate(updated, update);

    return item;
  }

  @override
  Future<void> deleteItineraryItem(String tripId, String itemId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
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
    _trips[_trips.indexOf(trip)] = _withUpdate(updated, update);
  }

  @override
  Future<void> reorderItineraryItems(
    String tripId,
    List<ItineraryItem> items,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    if (items.isEmpty) return;
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
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
    _trips[_trips.indexOf(trip)] = _withUpdate(updatedTrip, update);
  }

  @override
  Future<List<ItineraryItem>> getItinerary(
    String tripId, {
    DateTime? day,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    if (day == null) return trip.itinerary;
    return trip.getItemsForDay(trip.startDate.difference(day).inDays);
  }

  @override
  Future<Invite> createInvite({
    required String tripId,
    String? invitedEmail,
  }) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final invite = Invite(
      id: const Uuid().v4(),
      tripId: tripId,
      token: const Uuid().v4(),
      invitedEmail: invitedEmail,
      createdBy: _currentUserId,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(days: 30)),
    );
    _invites.add(invite);
    return invite;
  }

  @override
  Future<Invite?> getInviteByToken(String token) async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      return _invites.firstWhere((invite) => invite.token == token);
    } catch (e) {
      return null;
    }
  }

  @override
  Future<void> markInviteAsUsed(String inviteId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final index = _invites.indexWhere((invite) => invite.id == inviteId);
    if (index < 0) return;
    _invites[index] = _invites[index].copyWith(isUsed: true);
  }

  @override
  Future<void> publishTrip(String tripId, bool isPublished) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updated = trip.copyWith(
      isPublished: isPublished,
      updatedAt: DateTime.now(),
    );
    final update = _buildUpdate(
      text: isPublished
          ? 'Published the trip story.'
          : 'Unpublished the trip story.',
      kind: TripUpdateKind.story,
    );
    _trips[_trips.indexOf(trip)] = _withUpdate(updated, update);
  }

  @override
  Stream<List<Trip>> watchUserTrips() {
    final initialTrips =
        _trips
            .where((t) => t.members.any((m) => m.userId == _currentUserId))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return ConcatStream([
      Stream.value(initialTrips),
      Stream.periodic(const Duration(seconds: 5), (_) {
        return _trips
            .where((t) => t.members.any((m) => m.userId == _currentUserId))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      }),
    ]);
  }

  @override
  Stream<Trip?> watchTrip(String tripId) {
    Trip? getTrip() {
      try {
        return _trips.firstWhere((t) => t.id == tripId);
      } catch (e) {
        return null;
      }
    }

    return ConcatStream([
      Stream.value(getTrip()),
      Stream.periodic(const Duration(seconds: 5), (_) => getTrip()),
    ]);
  }

  @override
  Stream<List<ItineraryItem>> watchItinerary(String tripId) {
    List<ItineraryItem> getItems() {
      try {
        return _trips.firstWhere((t) => t.id == tripId).itinerary;
      } catch (e) {
        return [];
      }
    }

    return ConcatStream([
      Stream.value(getItems()),
      Stream.periodic(const Duration(seconds: 5), (_) => getItems()),
    ]);
  }

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return UserProfile(
      userId: userId,
      displayName: userId == _currentUserId ? 'You' : 'Jane Smith',
      email: userId == _currentUserId ? 'you@example.com' : 'jane@example.com',
      avatarUrl: null,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> updateUserProfile(UserProfile profile) async {
    await Future.delayed(const Duration(milliseconds: 200));
  }
}
