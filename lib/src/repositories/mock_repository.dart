import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/models/friends.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:uuid/uuid.dart';
import 'package:rxdart/rxdart.dart' show ConcatStream;

/// Mock implementation of TripRepository for development and testing.
class MockTripRepository implements TripRepository {
  final String _currentUserId;
  late List<Trip> _trips;
  final List<Invite> _invites = [];
  final Map<String, List<WallComment>> _tripComments = {};
  final Map<String, Map<String, List<ItineraryComment>>> _itemComments = {};
  final List<Friendship> _friendships = [];
  final List<FriendRequest> _friendRequests = [];
  final List<BlockedUser> _blockedUsers = [];
  final Map<String, UserProfile> _mockProfiles = {};

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

  void _appendSystemChatMessage(
    String tripId,
    String text, {
    String? actorId,
  }) {
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final message = ChatMessage(
      id: const Uuid().v4(),
      authorId: actorId ?? _currentUserId,
      text: text,
      createdAt: DateTime.now(),
      kind: ChatMessageKind.system,
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      chat: [...trip.chat, message],
      updatedAt: DateTime.now(),
    );
  }

  String _pairKey(String a, String b) {
    final ids = [a, b]..sort();
    return '${ids.first}_${ids.last}';
  }

  void _initMockData() {
    final now = DateTime.now();
    _mockProfiles
      ..clear()
      ..addAll({
        _currentUserId: UserProfile(
          userId: _currentUserId,
          displayName: 'You',
          handle: 'traveler_you',
          email: 'you@example.com',
          phone: '+1 415 555 0112',
          photoUrl: null,
          bio: 'Planning the next adventure.',
          createdAt: now.subtract(const Duration(days: 220)),
          updatedAt: now,
        ),
        'user_2': UserProfile(
          userId: 'user_2',
          displayName: 'Jane Smith',
          handle: 'janesmith',
          email: 'jane@example.com',
          phone: '+1 415 555 0129',
          photoUrl: null,
          bio: 'Chasing sunsets and good food.',
          createdAt: now.subtract(const Duration(days: 410)),
          updatedAt: now,
        ),
        'user_3': UserProfile(
          userId: 'user_3',
          displayName: 'Akshita Rao',
          handle: 'akshitar',
          email: 'akshita@example.com',
          phone: '+1 415 555 0148',
          photoUrl: null,
          bio: 'Planner by day, foodie by night.',
          createdAt: now.subtract(const Duration(days: 510)),
          updatedAt: now,
        ),
        'user_4': UserProfile(
          userId: 'user_4',
          displayName: 'Bhavesh Mehta',
          handle: 'bhaveshm',
          email: 'bhavesh@example.com',
          phone: '+1 415 555 0162',
          photoUrl: null,
          bio: 'Weekend explorer.',
          createdAt: now.subtract(const Duration(days: 180)),
          updatedAt: now,
        ),
        'user_5': UserProfile(
          userId: 'user_5',
          displayName: 'Nia Turner',
          handle: 'niat',
          email: 'nia@example.com',
          phone: '+1 415 555 0198',
          photoUrl: null,
          bio: 'Always booking the next flight.',
          createdAt: now.subtract(const Duration(days: 120)),
          updatedAt: now,
        ),
        'user_6': UserProfile(
          userId: 'user_6',
          displayName: 'Luca Romano',
          handle: 'lucar',
          email: 'luca@example.com',
          phone: '+39 334 555 0198',
          photoUrl: null,
          bio: 'Coffee, cameras, and coastlines.',
          createdAt: now.subtract(const Duration(days: 90)),
          updatedAt: now,
        ),
      });
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

    _friendships
      ..clear()
      ..addAll([
        Friendship(
          id: _pairKey(_currentUserId, 'user_2'),
          userIds: [_currentUserId, 'user_2'],
          createdAt: now.subtract(const Duration(days: 210)),
          lastInteractionAt: now.subtract(const Duration(days: 3)),
        ),
        Friendship(
          id: _pairKey(_currentUserId, 'user_3'),
          userIds: [_currentUserId, 'user_3'],
          createdAt: now.subtract(const Duration(days: 190)),
          lastInteractionAt: now.subtract(const Duration(days: 1)),
        ),
      ]);

    _friendRequests
      ..clear()
      ..addAll([
        FriendRequest(
          id: 'fr_1',
          fromUserId: 'user_5',
          toUserId: _currentUserId,
          status: FriendRequestStatus.pending,
          createdAt: now.subtract(const Duration(hours: 5)),
        ),
        FriendRequest(
          id: 'fr_2',
          fromUserId: _currentUserId,
          toUserId: 'user_6',
          status: FriendRequestStatus.pending,
          createdAt: now.subtract(const Duration(hours: 2)),
        ),
      ]);

    _blockedUsers.clear();

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

    for (final trip in _trips) {
      _tripComments[trip.id] = [...trip.story.wallComments];
    }
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
        personalItemsByUserId: {_currentUserId: const []},
        personalVisibilityByUserId: {_currentUserId: false},
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
    final existing = _tripComments[tripId] ?? [];
    final updatedComments = [...existing, comment];
    _tripComments[tripId] = updatedComments;
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
  Future<void> sendChatSystemMessage(String tripId, ChatMessage message) async {
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
  Future<void> toggleChatReaction(
    String tripId,
    String messageId,
    String emoji,
    bool add,
  ) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final messages = [...trip.chat];
    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final message = messages[index];
    final reactions = Map<String, List<String>>.from(message.reactions);
    final users = List<String>.from(reactions[emoji] ?? const <String>[]);
    if (add) {
      if (!users.contains(_currentUserId)) {
        users.add(_currentUserId);
      }
    } else {
      users.remove(_currentUserId);
    }
    if (users.isEmpty) {
      reactions.remove(emoji);
    } else {
      reactions[emoji] = users;
    }
    messages[index] = ChatMessage(
      id: message.id,
      authorId: message.authorId,
      text: message.text,
      createdAt: message.createdAt,
      kind: message.kind,
      mentions: message.mentions,
      itemRefs: message.itemRefs,
      replyToMessageId: message.replyToMessageId,
      reactions: reactions,
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      chat: messages,
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
    String? approvedUserId;
    if (status == JoinRequestStatus.approved) {
      final req = updatedRequests.firstWhere((r) => r.id == requestId);
      approvedUserId = req.userId;
      final exists = updatedMembers.any((m) => m.userId == req.userId);
      if (!exists) {
        updatedMembers = [
          ...updatedMembers,
          Member(
            userId: req.userId,
            name: 'Traveler',
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

    _trips[_trips.indexOf(trip)] = trip.copyWith(
      joinRequests: updatedRequests,
      members: updatedMembers,
      updatedAt: DateTime.now(),
    );
    if (approvedUserId != null) {
      _appendSystemChatMessage(
        tripId,
        'Traveler joined the trip.',
        actorId: approvedUserId,
      );
    }
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
      final updatedChecklist = _ensurePersonalChecklist(
        trip.checklist,
        member.userId,
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
      _appendSystemChatMessage(
        tripId,
        '${member.name} joined the trip.',
        actorId: member.userId,
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
    final memberName = trip.members
        .firstWhere(
          (m) => m.userId == userId,
          orElse: () => trip.members.first,
        )
        .name;
    final updatedChecklist = _removePersonalChecklist(
      trip.checklist,
      userId,
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      members: trip.members.where((m) => m.userId != userId).toList(),
      checklist: updatedChecklist,
      updatedAt: DateTime.now(),
    );
    _appendSystemChatMessage(
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
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
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

    _trips[_trips.indexOf(trip)] = trip.copyWith(
      ownerId: updatedOwnerId,
      members: updatedMembers,
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
    final existingIndex = trip.checklist.sharedItems.indexWhere(
      (s) => s.id == item.id,
    );
    final updatedShared = [...trip.checklist.sharedItems];
    if (existingIndex >= 0) {
      updatedShared[existingIndex] = item;
    } else {
      updatedShared.add(item);
    }
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: trip.checklist.copyWith(sharedItems: updatedShared),
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
    final updatedShared = trip.checklist.sharedItems
        .where((s) => s.id != itemId)
        .toList();
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: trip.checklist.copyWith(sharedItems: updatedShared),
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> upsertPersonalChecklistItem(
    String tripId,
    String ownerUserId,
    ChecklistItem item,
  ) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updatedChecklist = _upsertPersonalChecklistItem(
      trip.checklist,
      ownerUserId,
      item,
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: updatedChecklist,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> deletePersonalChecklistItem(
    String tripId,
    String ownerUserId,
    String itemId,
  ) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updatedChecklist = _deletePersonalChecklistItem(
      trip.checklist,
      ownerUserId,
      itemId,
    );
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: updatedChecklist,
      updatedAt: DateTime.now(),
    );
  }

  @override
  Future<void> setPersonalChecklistVisibility(
    String tripId,
    String ownerUserId,
    bool isShared,
  ) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final updatedVisibility = Map<String, bool>.from(
      trip.checklist.personalVisibilityByUserId,
    )
      ..[ownerUserId] = isShared;
    _trips[_trips.indexOf(trip)] = trip.copyWith(
      checklist: trip.checklist.copyWith(
        personalVisibilityByUserId: updatedVisibility,
      ),
      updatedAt: DateTime.now(),
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
    )
      ..remove(userId);
    final updatedVisibility = Map<String, bool>.from(
      checklist.personalVisibilityByUserId,
    )
      ..remove(userId);
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
  Future<ItineraryItem> upsertItineraryItem(
    String tripId,
    ItineraryItem item,
  ) async {
    await Future.delayed(const Duration(milliseconds: 200));
    final prepared = item.copyWith(
      createdBy: item.createdBy ?? _currentUserId,
      updatedBy: _currentUserId,
      updatedAt: DateTime.now(),
    );
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final existingIndex = trip.itinerary.indexWhere(
      (i) => i.id == prepared.id,
    );
    final existingItem = existingIndex >= 0
        ? trip.itinerary[existingIndex]
        : null;
    List<ItineraryItem> updatedItinerary;
    String updateText;

    if (existingIndex >= 0) {
      updatedItinerary = [...trip.itinerary];
      updatedItinerary[existingIndex] = prepared;
      if (existingItem != null &&
          existingItem.isCompleted != prepared.isCompleted) {
        updateText = prepared.isCompleted
            ? 'Completed: ${prepared.title}.'
            : 'Reopened: ${prepared.title}.';
      } else {
        updateText = 'Updated ${prepared.title}.';
      }
    } else {
      updatedItinerary = [...trip.itinerary, prepared];
      updateText = 'Added ${prepared.title}.';
    }

    final updated = trip.copyWith(
      itinerary: updatedItinerary,
      updatedAt: DateTime.now(),
    );
    final update = _buildUpdate(text: updateText, kind: TripUpdateKind.planner);
    _trips[_trips.indexOf(trip)] = _withUpdate(updated, update);
    _appendSystemChatMessage(
      tripId,
      existingIndex >= 0
          ? 'Updated itinerary: ${prepared.title}.'
          : 'Added to itinerary: ${prepared.title}.',
    );

    return prepared;
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
    _appendSystemChatMessage(
      tripId,
      'Updated itinerary: Removed ${removedItem.title}.',
    );
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
      final override = updatesById[item.id];
      if (override == null) return item;
      return override.copyWith(
        updatedBy: _currentUserId,
        updatedAt: DateTime.now(),
      );
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
    _appendSystemChatMessage(
      tripId,
      'Updated itinerary: Reordered the day plan.',
    );
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
    MemberRole role = MemberRole.viewer,
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
      role: role,
    );
    _invites.add(invite);
    return invite;
  }

  @override
  Future<Invite?> getInviteByToken(String token) async {
    await Future.delayed(const Duration(milliseconds: 200));
    try {
      return _invites.firstWhere((invite) => invite.token == token);
    } catch (_) {
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
  Future<List<ItineraryCategory>> getItineraryCategories() async {
    return const [
      ItineraryCategory(id: 'flight', label: 'Flight', icon: 'flight', order: 0),
      ItineraryCategory(
        id: 'lodging',
        label: 'Lodging',
        icon: 'hotel',
        order: 1,
      ),
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
  }

  @override
  Stream<List<WallComment>> watchTripComments(String tripId, {int limit = 100}) {
    List<WallComment> getComments() {
      return (_tripComments[tripId] ?? []).take(limit).toList();
    }

    return ConcatStream([
      Stream.value(getComments()),
      Stream.periodic(const Duration(seconds: 5), (_) => getComments()),
    ]);
  }

  @override
  Stream<List<ChatMessage>> watchChatMessages(
    String tripId, {
    int limit = 50,
  }) {
    List<ChatMessage> getMessages() {
      try {
        final trip = _trips.firstWhere((t) => t.id == tripId);
        final sorted = [...trip.chat]
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
        if (sorted.length <= limit) return sorted;
        return sorted.sublist(sorted.length - limit);
      } catch (_) {
        return [];
      }
    }

    return ConcatStream([
      Stream.value(getMessages()),
      Stream.periodic(const Duration(seconds: 5), (_) => getMessages()),
    ]);
  }

  @override
  Future<List<ChatMessage>> fetchChatMessagesPage(
    String tripId, {
    int limit = 50,
    ChatMessagesCursor? before,
  }) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final trip = _trips.firstWhere(
      (t) => t.id == tripId,
      orElse: () => throw Exception('Trip not found'),
    );
    final sorted = [...trip.chat]
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    if (before == null) {
      if (sorted.length <= limit) return sorted;
      return sorted.sublist(sorted.length - limit);
    }
    final older = sorted.where((message) {
      if (message.createdAt.isBefore(before.createdAt)) return true;
      if (message.createdAt.isAtSameMomentAs(before.createdAt) &&
          message.id != before.messageId) {
        return true;
      }
      return false;
    }).toList();
    if (older.length <= limit) return older;
    return older.sublist(older.length - limit);
  }

  @override
  Stream<List<ItineraryComment>> watchItineraryComments(
    String tripId,
    String itemId,
  ) {
    List<ItineraryComment> getComments() {
      return (_itemComments[tripId]?[itemId] ?? []).toList();
    }

    return ConcatStream([
      Stream.value(getComments()),
      Stream.periodic(const Duration(seconds: 5), (_) => getComments()),
    ]);
  }

  @override
  Future<void> addItineraryComment(
    String tripId,
    String itemId,
    ItineraryComment comment,
  ) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final tripMap = _itemComments.putIfAbsent(tripId, () => {});
    final existing = tripMap[itemId] ?? [];
    tripMap[itemId] = [...existing, comment];
  }

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    await Future.delayed(const Duration(milliseconds: 200));
    return _mockProfiles[userId];
  }

  @override
  Future<void> updateUserProfile(UserProfile profile) async {
    await Future.delayed(const Duration(milliseconds: 200));
    _mockProfiles[profile.userId] = profile;
  }

  @override
  Future<bool> isHandleAvailable(
    String handle, {
    String? excludeUserId,
  }) async {
    await Future.delayed(const Duration(milliseconds: 120));
    final normalized = handle.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    for (final entry in _mockProfiles.entries) {
      if (excludeUserId != null && entry.key == excludeUserId) continue;
      if ((entry.value.handle ?? '').toLowerCase() == normalized) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<List<UserProfile>> searchUserProfiles(String query) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return [];
    return _mockProfiles.values
        .where((profile) {
          if (profile.userId == _currentUserId) return false;
          final values = [
            profile.displayName,
            profile.handle ?? '',
            profile.email ?? '',
            profile.phone ?? '',
          ];
          return values.any((value) => value.toLowerCase().contains(trimmed));
        })
        .toList();
  }

  @override
  Stream<List<Friendship>> watchFriends() {
    List<Friendship> getFriends() {
      return _friendships
          .where((friendship) =>
              friendship.userIds.contains(_currentUserId))
          .toList();
    }

    return ConcatStream([
      Stream.value(getFriends()),
      Stream.periodic(const Duration(seconds: 5), (_) => getFriends()),
    ]);
  }

  @override
  Stream<List<FriendRequest>> watchIncomingFriendRequests() {
    List<FriendRequest> getRequests() {
      return _friendRequests
          .where((request) =>
              request.toUserId == _currentUserId &&
              request.status == FriendRequestStatus.pending)
          .toList();
    }

    return ConcatStream([
      Stream.value(getRequests()),
      Stream.periodic(const Duration(seconds: 5), (_) => getRequests()),
    ]);
  }

  @override
  Stream<List<FriendRequest>> watchOutgoingFriendRequests() {
    List<FriendRequest> getRequests() {
      return _friendRequests
          .where((request) =>
              request.fromUserId == _currentUserId &&
              request.status == FriendRequestStatus.pending)
          .toList();
    }

    return ConcatStream([
      Stream.value(getRequests()),
      Stream.periodic(const Duration(seconds: 5), (_) => getRequests()),
    ]);
  }

  @override
  Future<void> sendFriendRequest(String toUserId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (toUserId.isEmpty || toUserId == _currentUserId) return;
    if (_blockedUsers.any((entry) =>
        entry.blockerId == _currentUserId &&
        entry.blockedUserId == toUserId)) {
      return;
    }
    if (_blockedUsers.any((entry) =>
        entry.blockerId == toUserId &&
        entry.blockedUserId == _currentUserId)) {
      return;
    }
    if (_friendships.any((friendship) =>
        friendship.userIds.contains(_currentUserId) &&
        friendship.userIds.contains(toUserId))) {
      return;
    }
    if (_friendRequests.any((request) =>
        request.fromUserId == _currentUserId &&
        request.toUserId == toUserId &&
        request.status == FriendRequestStatus.pending)) {
      return;
    }
    _friendRequests.add(
      FriendRequest(
        id: const Uuid().v4(),
        fromUserId: _currentUserId,
        toUserId: toUserId,
        status: FriendRequestStatus.pending,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<void> respondToFriendRequest(
    String requestId,
    FriendRequestStatus status,
  ) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _friendRequests.indexWhere((r) => r.id == requestId);
    if (index < 0) return;
    final request = _friendRequests[index];
    if (request.toUserId != _currentUserId) return;
    _friendRequests[index] = request.copyWith(
      status: status,
      respondedAt: DateTime.now(),
    );
    if (status == FriendRequestStatus.accepted) {
      _friendships.add(
        Friendship(
          id: _pairKey(request.fromUserId, request.toUserId),
          userIds: [request.fromUserId, request.toUserId],
          createdAt: DateTime.now(),
          lastInteractionAt: DateTime.now(),
        ),
      );
    }
  }

  @override
  Future<void> cancelFriendRequest(String requestId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    final index = _friendRequests.indexWhere((r) => r.id == requestId);
    if (index < 0) return;
    final request = _friendRequests[index];
    if (request.fromUserId != _currentUserId) return;
    _friendRequests[index] = request.copyWith(
      status: FriendRequestStatus.canceled,
      respondedAt: DateTime.now(),
    );
  }

  @override
  Future<void> removeFriend(String friendUserId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _friendships.removeWhere((friendship) =>
        friendship.userIds.contains(_currentUserId) &&
        friendship.userIds.contains(friendUserId));
  }

  @override
  Future<void> blockUser(String blockedUserId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    if (blockedUserId.isEmpty || blockedUserId == _currentUserId) return;
    final existing = _blockedUsers.indexWhere((entry) =>
        entry.blockerId == _currentUserId &&
        entry.blockedUserId == blockedUserId);
    if (existing >= 0) return;
    _blockedUsers.add(
      BlockedUser(
        id: '${_currentUserId}_$blockedUserId',
        blockerId: _currentUserId,
        blockedUserId: blockedUserId,
        createdAt: DateTime.now(),
      ),
    );
    _friendships.removeWhere((friendship) =>
        friendship.userIds.contains(_currentUserId) &&
        friendship.userIds.contains(blockedUserId));
    _friendRequests.removeWhere((request) =>
        (request.fromUserId == _currentUserId &&
            request.toUserId == blockedUserId &&
            request.status == FriendRequestStatus.pending) ||
        (request.fromUserId == blockedUserId &&
            request.toUserId == _currentUserId &&
            request.status == FriendRequestStatus.pending));
  }

  @override
  Future<void> unblockUser(String blockedUserId) async {
    await Future.delayed(const Duration(milliseconds: 150));
    _blockedUsers.removeWhere((entry) =>
        entry.blockerId == _currentUserId &&
        entry.blockedUserId == blockedUserId);
  }

  @override
  Stream<List<BlockedUser>> watchBlockedUsers() {
    List<BlockedUser> getBlocked() {
      return _blockedUsers
          .where((entry) => entry.blockerId == _currentUserId)
          .toList();
    }

    return ConcatStream([
      Stream.value(getBlocked()),
      Stream.periodic(const Duration(seconds: 5), (_) => getBlocked()),
    ]);
  }
}
