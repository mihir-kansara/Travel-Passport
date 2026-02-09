/// Represents a trip/passport with destination, dates, and shared planning data.
class Trip {
  final String id;
  final String ownerId;
  final String destination;
  final DateTime startDate;
  final DateTime endDate;
  final String description;
  final TripVisibility visibility;
  final List<Member> members;
  final List<ItineraryItem> itinerary;
  final TripAudience audience;
  final List<TripUpdate> updates;
  final TripChecklist checklist;
  final List<JoinRequest> joinRequests;
  final List<ChatMessage> chat;
  final TripStory story;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool
  isPublished; // Whether the trip has been published as a public story
  final String? heroImageUrl; // Image for trip card/hero section
  final int? coverGradientId; // Gradient preset for cover when no image

  Trip({
    required this.id,
    required this.ownerId,
    required this.destination,
    required this.startDate,
    required this.endDate,
    required this.description,
    this.visibility = TripVisibility.inviteOnly,
    this.members = const [],
    this.itinerary = const [],
    this.audience = const TripAudience(),
    this.updates = const [],
    this.checklist = const TripChecklist(),
    this.joinRequests = const [],
    this.chat = const [],
    TripStory? story,
    required this.createdAt,
    required this.updatedAt,
    this.isPublished = false,
    this.heroImageUrl,
    this.coverGradientId,
  }) : story = story ?? const TripStory();

  /// Duration of the trip in days.
  int get durationDays => endDate.difference(startDate).inDays + 1;

  bool get isPast => endDate.isBefore(DateTime.now());

  bool get isUpcoming => !isPast;

  /// Return all day indices covered by this trip (0-indexed).
  List<int> getTripDays() => List.generate(durationDays, (i) => i);

  /// Get items for a specific day (0-indexed relative to trip start).
  List<ItineraryItem> getItemsForDay(int dayIndex) {
    if (dayIndex < 0 || dayIndex >= durationDays) return [];
    final dayDate = startDate.add(Duration(days: dayIndex));
    return itinerary
        .where(
          (item) =>
              item.dateTime.year == dayDate.year &&
              item.dateTime.month == dayDate.month &&
              item.dateTime.day == dayDate.day,
        )
        .toList();
  }

  /// Create a copy with modified fields.
  Trip copyWith({
    String? id,
    String? ownerId,
    String? destination,
    DateTime? startDate,
    DateTime? endDate,
    String? description,
    TripVisibility? visibility,
    List<Member>? members,
    List<ItineraryItem>? itinerary,
    TripAudience? audience,
    List<TripUpdate>? updates,
    TripChecklist? checklist,
    List<JoinRequest>? joinRequests,
    List<ChatMessage>? chat,
    TripStory? story,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isPublished,
    String? heroImageUrl,
    int? coverGradientId,
  }) {
    return Trip(
      id: id ?? this.id,
      ownerId: ownerId ?? this.ownerId,
      destination: destination ?? this.destination,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      description: description ?? this.description,
      visibility: visibility ?? this.visibility,
      members: members ?? this.members,
      itinerary: itinerary ?? this.itinerary,
      audience: audience ?? this.audience,
      updates: updates ?? this.updates,
      checklist: checklist ?? this.checklist,
      joinRequests: joinRequests ?? this.joinRequests,
      chat: chat ?? this.chat,
      story: story ?? this.story,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isPublished: isPublished ?? this.isPublished,
      heroImageUrl: heroImageUrl ?? this.heroImageUrl,
      coverGradientId: coverGradientId ?? this.coverGradientId,
    );
  }

  /// Convert to JSON map (for serialization/Storage).
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ownerId': ownerId,
      'destination': destination,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'description': description,
      'visibility': visibility.name,
      'members': members.map((m) => m.toFirestore()).toList(),
      'itinerary': itinerary.map((i) => i.toFirestore()).toList(),
      'audience': audience.toJson(),
      'updates': updates.map((u) => u.toJson()).toList(),
      'checklist': checklist.toJson(),
      'joinRequests': joinRequests.map((r) => r.toJson()).toList(),
      'chat': chat.map((c) => c.toJson()).toList(),
      'story': story.toJson(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isPublished': isPublished,
      'heroImageUrl': heroImageUrl,
      'coverGradientId': coverGradientId,
    };
  }

  /// Create from JSON map.
  factory Trip.fromJson(Map<String, dynamic> data) {
    return Trip(
      id: data['id'] as String? ?? '',
      ownerId: data['ownerId'] as String? ?? '',
      destination: data['destination'] as String? ?? '',
      startDate: data['startDate'] != null
          ? DateTime.parse(data['startDate'] as String)
          : DateTime.now(),
      endDate: data['endDate'] != null
          ? DateTime.parse(data['endDate'] as String)
          : DateTime.now(),
      description: data['description'] as String? ?? '',
      visibility: TripVisibility.values.firstWhere(
        (v) => v.name == (data['visibility'] as String?),
        orElse: () => TripVisibility.inviteOnly,
      ),
      members:
          (data['members'] as List<dynamic>?)
              ?.map((m) => Member.fromFirestore(m as Map<String, dynamic>))
              .toList() ??
          [],
      itinerary:
          (data['itinerary'] as List<dynamic>?)
              ?.map(
                (i) => ItineraryItem.fromFirestore(i as Map<String, dynamic>),
              )
              .toList() ??
          [],
      audience: data['audience'] != null
          ? TripAudience.fromJson(data['audience'] as Map<String, dynamic>)
          : const TripAudience(),
      updates:
          (data['updates'] as List<dynamic>?)
              ?.map((u) => TripUpdate.fromJson(u as Map<String, dynamic>))
              .toList() ??
          [],
      checklist: data['checklist'] != null
          ? TripChecklist.fromJson(data['checklist'] as Map<String, dynamic>)
          : const TripChecklist(),
      joinRequests:
          (data['joinRequests'] as List<dynamic>?)
              ?.map((r) => JoinRequest.fromJson(r as Map<String, dynamic>))
              .toList() ??
          [],
      chat:
          (data['chat'] as List<dynamic>?)
              ?.map((c) => ChatMessage.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      story: data['story'] != null
          ? TripStory.fromJson(data['story'] as Map<String, dynamic>)
          : const TripStory(),
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? DateTime.parse(data['updatedAt'] as String)
          : DateTime.now(),
      isPublished: data['isPublished'] as bool? ?? false,
      heroImageUrl: data['heroImageUrl'] as String?,
      coverGradientId: data['coverGradientId'] as int?,
    );
  }

  /// Convert to Firestore document map (deprecated - will be used when Firebase is enabled).
  @Deprecated('Use toJson() instead. Firestore will be restored in Phase 2.')
  Map<String, dynamic> toFirestore() => toJson();

  /// Create from Firestore document map (deprecated - will be used when Firebase is enabled).
  @Deprecated(
    'Use Trip.fromJson() instead. Firestore will be restored in Phase 2.',
  )
  factory Trip.fromFirestore(Map<String, dynamic> data) => Trip.fromJson(data);

  @override
  String toString() =>
      'Trip(id: $id, destination: $destination, members: ${members.length})';
}

class TripAudience {
  final TripVisibility visibility;
  final bool allowJoinRequests;
  final JoinApproval joinApproval;

  const TripAudience({
    this.visibility = TripVisibility.inviteOnly,
    this.allowJoinRequests = true,
    this.joinApproval = JoinApproval.owner,
  });

  TripAudience copyWith({
    TripVisibility? visibility,
    bool? allowJoinRequests,
    JoinApproval? joinApproval,
  }) {
    return TripAudience(
      visibility: visibility ?? this.visibility,
      allowJoinRequests: allowJoinRequests ?? this.allowJoinRequests,
      joinApproval: joinApproval ?? this.joinApproval,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'visibility': visibility.name,
      'allowJoinRequests': allowJoinRequests,
      'joinApproval': joinApproval.name,
    };
  }

  factory TripAudience.fromJson(Map<String, dynamic> data) {
    return TripAudience(
      visibility: TripVisibility.values.firstWhere(
        (v) => v.name == (data['visibility'] as String?),
        orElse: () => TripVisibility.inviteOnly,
      ),
      allowJoinRequests: data['allowJoinRequests'] as bool? ?? true,
      joinApproval: JoinApproval.values.firstWhere(
        (v) => v.name == (data['joinApproval'] as String?),
        orElse: () => JoinApproval.owner,
      ),
    );
  }
}

class TripStory {
  final String headline;
  final List<String> highlights;
  final List<StoryPhoto> photos;
  final List<StoryMoment> moments;
  final WallStats wallStats;
  final List<WallComment> wallComments;
  final List<String> likedBy;
  final bool publishToWall;
  final bool isLive;
  final bool isArchived;

  const TripStory({
    this.headline = '',
    this.highlights = const [],
    this.photos = const [],
    this.moments = const [],
    this.wallStats = const WallStats(),
    this.wallComments = const [],
    this.likedBy = const [],
    this.publishToWall = false,
    this.isLive = true,
    this.isArchived = false,
  });

  TripStory copyWith({
    String? headline,
    List<String>? highlights,
    List<StoryPhoto>? photos,
    List<StoryMoment>? moments,
    WallStats? wallStats,
    List<WallComment>? wallComments,
    List<String>? likedBy,
    bool? publishToWall,
    bool? isLive,
    bool? isArchived,
  }) {
    return TripStory(
      headline: headline ?? this.headline,
      highlights: highlights ?? this.highlights,
      photos: photos ?? this.photos,
      moments: moments ?? this.moments,
      wallStats: wallStats ?? this.wallStats,
      wallComments: wallComments ?? this.wallComments,
      likedBy: likedBy ?? this.likedBy,
      publishToWall: publishToWall ?? this.publishToWall,
      isLive: isLive ?? this.isLive,
      isArchived: isArchived ?? this.isArchived,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'headline': headline,
      'highlights': highlights,
      'photos': photos.map((p) => p.toJson()).toList(),
      'moments': moments.map((m) => m.toJson()).toList(),
      'wallStats': wallStats.toJson(),
      'wallComments': wallComments.map((c) => c.toJson()).toList(),
      'likedBy': likedBy,
      'publishToWall': publishToWall,
      'isLive': isLive,
      'isArchived': isArchived,
    };
  }

  factory TripStory.fromJson(Map<String, dynamic> data) {
    return TripStory(
      headline: data['headline'] as String? ?? '',
      highlights: List<String>.from(data['highlights'] as List? ?? []),
      photos:
          (data['photos'] as List<dynamic>?)
              ?.map((p) => StoryPhoto.fromJson(p as Map<String, dynamic>))
              .toList() ??
          [],
      moments:
          (data['moments'] as List<dynamic>?)
              ?.map((m) => StoryMoment.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      wallStats: data['wallStats'] != null
          ? WallStats.fromJson(data['wallStats'] as Map<String, dynamic>)
          : const WallStats(),
      wallComments:
          (data['wallComments'] as List<dynamic>?)
              ?.map((c) => WallComment.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      likedBy: List<String>.from(data['likedBy'] as List? ?? []),
      publishToWall: data['publishToWall'] as bool? ?? false,
      isLive: data['isLive'] as bool? ?? true,
      isArchived: data['isArchived'] as bool? ?? false,
    );
  }
}

class StoryPhoto {
  final String id;
  final String url;
  final String caption;

  const StoryPhoto({required this.id, required this.url, this.caption = ''});

  Map<String, dynamic> toJson() {
    return {'id': id, 'url': url, 'caption': caption};
  }

  factory StoryPhoto.fromJson(Map<String, dynamic> data) {
    return StoryPhoto(
      id: data['id'] as String? ?? '',
      url: data['url'] as String? ?? '',
      caption: data['caption'] as String? ?? '',
    );
  }
}

class StoryMoment {
  final String id;
  final String authorId;
  final String caption;
  final DateTime createdAt;
  final StoryMomentType type;
  final String? imageUrl;
  final bool isPublic;

  const StoryMoment({
    required this.id,
    required this.authorId,
    required this.caption,
    required this.createdAt,
    this.type = StoryMomentType.text,
    this.imageUrl,
    this.isPublic = true,
  });

  StoryMoment copyWith({
    String? id,
    String? authorId,
    String? caption,
    DateTime? createdAt,
    StoryMomentType? type,
    String? imageUrl,
    bool? isPublic,
  }) {
    return StoryMoment(
      id: id ?? this.id,
      authorId: authorId ?? this.authorId,
      caption: caption ?? this.caption,
      createdAt: createdAt ?? this.createdAt,
      type: type ?? this.type,
      imageUrl: imageUrl ?? this.imageUrl,
      isPublic: isPublic ?? this.isPublic,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'caption': caption,
      'createdAt': createdAt.toIso8601String(),
      'type': type.name,
      'imageUrl': imageUrl,
      'isPublic': isPublic,
    };
  }

  factory StoryMoment.fromJson(Map<String, dynamic> data) {
    return StoryMoment(
      id: data['id'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      caption: data['caption'] as String? ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
      type: StoryMomentType.values.firstWhere(
        (t) => t.name == (data['type'] as String?),
        orElse: () => StoryMomentType.text,
      ),
      imageUrl: data['imageUrl'] as String?,
      isPublic: data['isPublic'] as bool? ?? true,
    );
  }
}

class WallStats {
  final int likes;
  final int comments;

  const WallStats({this.likes = 0, this.comments = 0});

  WallStats copyWith({int? likes, int? comments}) {
    return WallStats(
      likes: likes ?? this.likes,
      comments: comments ?? this.comments,
    );
  }

  Map<String, dynamic> toJson() {
    return {'likes': likes, 'comments': comments};
  }

  factory WallStats.fromJson(Map<String, dynamic> data) {
    return WallStats(
      likes: data['likes'] as int? ?? 0,
      comments: data['comments'] as int? ?? 0,
    );
  }
}

class WallComment {
  final String id;
  final String authorId;
  final String text;
  final DateTime createdAt;

  const WallComment({
    required this.id,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory WallComment.fromJson(Map<String, dynamic> data) {
    return WallComment(
      id: data['id'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

class TripUpdate {
  final String id;
  final String actorId;
  final String text;
  final TripUpdateKind kind;
  final DateTime createdAt;

  const TripUpdate({
    required this.id,
    required this.actorId,
    required this.text,
    this.kind = TripUpdateKind.system,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'actorId': actorId,
      'text': text,
      'kind': kind.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory TripUpdate.fromJson(Map<String, dynamic> data) {
    return TripUpdate(
      id: data['id'] as String? ?? '',
      actorId: data['actorId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      kind: TripUpdateKind.values.firstWhere(
        (k) => k.name == (data['kind'] as String?),
        orElse: () => TripUpdateKind.system,
      ),
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

class TripChecklist {
  final List<MemberChecklist> members;
  final List<ChecklistItem> shared;

  const TripChecklist({this.members = const [], this.shared = const []});

  TripChecklist copyWith({
    List<MemberChecklist>? members,
    List<ChecklistItem>? shared,
  }) {
    return TripChecklist(
      members: members ?? this.members,
      shared: shared ?? this.shared,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'members': members.map((m) => m.toJson()).toList(),
      'shared': shared.map((s) => s.toJson()).toList(),
    };
  }

  factory TripChecklist.fromJson(Map<String, dynamic> data) {
    return TripChecklist(
      members:
          (data['members'] as List<dynamic>?)
              ?.map((m) => MemberChecklist.fromJson(m as Map<String, dynamic>))
              .toList() ??
          [],
      shared:
          (data['shared'] as List<dynamic>?)
              ?.map((s) => ChecklistItem.fromJson(s as Map<String, dynamic>))
              .toList() ??
          [],
    );
  }
}

class MemberChecklist {
  final String userId;
  final bool flightBooked;
  final bool hotelBooked;
  final bool reservationsBooked;
  final bool passportReady;
  final DateTime updatedAt;

  const MemberChecklist({
    required this.userId,
    this.flightBooked = false,
    this.hotelBooked = false,
    this.reservationsBooked = false,
    this.passportReady = false,
    required this.updatedAt,
  });

  MemberChecklist copyWith({
    bool? flightBooked,
    bool? hotelBooked,
    bool? reservationsBooked,
    bool? passportReady,
    DateTime? updatedAt,
  }) {
    return MemberChecklist(
      userId: userId,
      flightBooked: flightBooked ?? this.flightBooked,
      hotelBooked: hotelBooked ?? this.hotelBooked,
      reservationsBooked: reservationsBooked ?? this.reservationsBooked,
      passportReady: passportReady ?? this.passportReady,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'flightBooked': flightBooked,
      'hotelBooked': hotelBooked,
      'reservationsBooked': reservationsBooked,
      'passportReady': passportReady,
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory MemberChecklist.fromJson(Map<String, dynamic> data) {
    return MemberChecklist(
      userId: data['userId'] as String? ?? '',
      flightBooked: data['flightBooked'] as bool? ?? false,
      hotelBooked: data['hotelBooked'] as bool? ?? false,
      reservationsBooked: data['reservationsBooked'] as bool? ?? false,
      passportReady: data['passportReady'] as bool? ?? false,
      updatedAt: data['updatedAt'] != null
          ? DateTime.parse(data['updatedAt'] as String)
          : DateTime.now(),
    );
  }
}

class ChecklistItem {
  final String id;
  final String title;
  final bool isDone;
  final DateTime createdAt;
  final DateTime updatedAt;

  const ChecklistItem({
    required this.id,
    required this.title,
    this.isDone = false,
    required this.createdAt,
    required this.updatedAt,
  });

  ChecklistItem copyWith({String? title, bool? isDone, DateTime? updatedAt}) {
    return ChecklistItem(
      id: id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'isDone': isDone,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory ChecklistItem.fromJson(Map<String, dynamic> data) {
    return ChecklistItem(
      id: data['id'] as String? ?? '',
      title: data['title'] as String? ?? '',
      isDone: data['isDone'] as bool? ?? false,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? DateTime.parse(data['updatedAt'] as String)
          : DateTime.now(),
    );
  }
}

class JoinRequest {
  final String id;
  final String userId;
  final String note;
  final JoinRequestStatus status;
  final DateTime createdAt;

  const JoinRequest({
    required this.id,
    required this.userId,
    this.note = '',
    this.status = JoinRequestStatus.pending,
    required this.createdAt,
  });

  JoinRequest copyWith({JoinRequestStatus? status}) {
    return JoinRequest(
      id: id,
      userId: userId,
      note: note,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'note': note,
      'status': status.name,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory JoinRequest.fromJson(Map<String, dynamic> data) {
    return JoinRequest(
      id: data['id'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      note: data['note'] as String? ?? '',
      status: JoinRequestStatus.values.firstWhere(
        (s) => s.name == (data['status'] as String?),
        orElse: () => JoinRequestStatus.pending,
      ),
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

class ChatMessage {
  final String id;
  final String authorId;
  final String text;
  final DateTime createdAt;

  const ChatMessage({
    required this.id,
    required this.authorId,
    required this.text,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'authorId': authorId,
      'text': text,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ChatMessage.fromJson(Map<String, dynamic> data) {
    return ChatMessage(
      id: data['id'] as String? ?? '',
      authorId: data['authorId'] as String? ?? '',
      text: data['text'] as String? ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
    );
  }
}

/// Represents an item in the trip itinerary (activity, stay, food, note, etc.).
class ItineraryItem {
  final String id;
  final String tripId;
  final DateTime dateTime;
  final String title;
  final String? description;
  final String? notes;
  final ItineraryItemType type;
  final String? location;
  final String? imageUrl;
  final String? assignedTo; // User ID of assigned member
  final String? assigneeId;
  final String? assigneeName;
  final String? link;
  final bool isCompleted;
  final ItineraryStatus status;
  final int order; // Sort order within the day
  final DateTime createdAt;
  final DateTime updatedAt;

  ItineraryItem({
    required this.id,
    required this.tripId,
    required this.dateTime,
    required this.title,
    this.description,
    this.notes,
    this.type = ItineraryItemType.activity,
    this.location,
    this.imageUrl,
    this.assignedTo,
    this.assigneeId,
    this.assigneeName,
    this.link,
    this.isCompleted = false,
    this.status = ItineraryStatus.planned,
    this.order = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Create a copy with modified fields.
  ItineraryItem copyWith({
    String? id,
    String? tripId,
    DateTime? dateTime,
    String? title,
    String? description,
    String? notes,
    ItineraryItemType? type,
    String? location,
    String? imageUrl,
    String? assignedTo,
    String? assigneeId,
    String? assigneeName,
    String? link,
    bool? isCompleted,
    ItineraryStatus? status,
    int? order,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ItineraryItem(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      dateTime: dateTime ?? this.dateTime,
      title: title ?? this.title,
      description: description ?? this.description,
      notes: notes ?? this.notes,
      type: type ?? this.type,
      location: location ?? this.location,
      imageUrl: imageUrl ?? this.imageUrl,
      assignedTo: assignedTo ?? this.assignedTo,
      assigneeId: assigneeId ?? this.assigneeId,
      assigneeName: assigneeName ?? this.assigneeName,
      link: link ?? this.link,
      isCompleted: isCompleted ?? this.isCompleted,
      status: status ?? this.status,
      order: order ?? this.order,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Convert to Firestore document map.
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'tripId': tripId,
      'dateTime': dateTime.toIso8601String(),
      'title': title,
      'description': description,
      'notes': notes,
      'type': type.name,
      'location': location,
      'imageUrl': imageUrl,
      'assignedTo': assignedTo,
      'assigneeId': assigneeId,
      'assigneeName': assigneeName,
      'link': link,
      'isCompleted': isCompleted,
      'status': status.name,
      'order': order,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  /// Create from Firestore document map.
  factory ItineraryItem.fromFirestore(Map<String, dynamic> data) {
    final assignedTo = data['assignedTo'] as String?;
    return ItineraryItem(
      id: data['id'] as String? ?? '',
      tripId: data['tripId'] as String? ?? '',
      dateTime: data['dateTime'] != null
          ? DateTime.parse(data['dateTime'] as String)
          : DateTime.now(),
      title: data['title'] as String? ?? '',
      description: data['description'] as String?,
      notes: data['notes'] as String?,
      type: ItineraryItemType.values.firstWhere(
        (t) => t.name == (data['type'] as String?),
        orElse: () => ItineraryItemType.activity,
      ),
      location: data['location'] as String?,
      imageUrl: data['imageUrl'] as String?,
      assignedTo: assignedTo,
      assigneeId: data['assigneeId'] as String? ?? assignedTo,
      assigneeName: data['assigneeName'] as String?,
      link: data['link'] as String?,
      isCompleted: data['isCompleted'] as bool? ?? false,
      status: _statusFromData(
        data['status'] as String?,
        data['isCompleted'] as bool? ?? false,
      ),
      order: data['order'] as int? ?? 0,
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
      updatedAt: data['updatedAt'] != null
          ? DateTime.parse(data['updatedAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  String toString() => 'ItineraryItem(id: $id, title: $title, type: $type)';
}

/// Represents a member/collaborator in a trip.
class Member {
  final String userId;
  final String name;
  final String? email;
  final String? avatarUrl;
  final MemberRole role;
  final DateTime joinedAt;

  Member({
    required this.userId,
    required this.name,
    this.email,
    this.avatarUrl,
    this.role = MemberRole.collaborator,
    required this.joinedAt,
  });

  /// Create a copy with modified fields.
  Member copyWith({
    String? userId,
    String? name,
    String? email,
    String? avatarUrl,
    MemberRole? role,
    DateTime? joinedAt,
  }) {
    return Member(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }

  /// Convert to Firestore document map.
  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'avatarUrl': avatarUrl,
      'role': role.name,
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  /// Create from Firestore document map.
  factory Member.fromFirestore(Map<String, dynamic> data) {
    return Member(
      userId: data['userId'] as String? ?? '',
      name: data['name'] as String? ?? '',
      email: data['email'] as String?,
      avatarUrl: data['avatarUrl'] as String?,
      role: MemberRole.values.firstWhere(
        (r) => r.name == (data['role'] as String?),
        orElse: () => MemberRole.collaborator,
      ),
      joinedAt: data['joinedAt'] != null
          ? DateTime.parse(data['joinedAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  String toString() => 'Member(userId: $userId, name: $name, role: $role)';
}

/// Represents a pending invitation to a trip (via link or email).
class Invite {
  final String id;
  final String tripId;
  final String token; // Unique token for the invite link
  final String? invitedEmail; // If null, it's a public link invite
  final String createdBy;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isUsed;

  Invite({
    required this.id,
    required this.tripId,
    required this.token,
    this.invitedEmail,
    required this.createdBy,
    required this.createdAt,
    required this.expiresAt,
    this.isUsed = false,
  });

  /// Check if invite is still valid.
  bool get isValid => !isUsed && DateTime.now().isBefore(expiresAt);

  /// Create a copy with modified fields.
  Invite copyWith({
    String? id,
    String? tripId,
    String? token,
    String? invitedEmail,
    String? createdBy,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? isUsed,
  }) {
    return Invite(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      token: token ?? this.token,
      invitedEmail: invitedEmail ?? this.invitedEmail,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isUsed: isUsed ?? this.isUsed,
    );
  }

  /// Convert to Firestore document map.
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'tripId': tripId,
      'token': token,
      'invitedEmail': invitedEmail,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'expiresAt': expiresAt.toIso8601String(),
      'isUsed': isUsed,
    };
  }

  /// Create from Firestore document map.
  factory Invite.fromFirestore(Map<String, dynamic> data) {
    return Invite(
      id: data['id'] as String? ?? '',
      tripId: data['tripId'] as String? ?? '',
      token: data['token'] as String? ?? '',
      invitedEmail: data['invitedEmail'] as String?,
      createdBy: data['createdBy'] as String? ?? '',
      createdAt: data['createdAt'] != null
          ? DateTime.parse(data['createdAt'] as String)
          : DateTime.now(),
      expiresAt: data['expiresAt'] != null
          ? DateTime.parse(data['expiresAt'] as String)
          : DateTime.now(),
      isUsed: data['isUsed'] as bool? ?? false,
    );
  }

  @override
  String toString() => 'Invite(id: $id, tripId: $tripId, valid: $isValid)';
}

/// Enum for trip visibility (privacy).
enum TripVisibility {
  inviteOnly, // Only invited members can see
  friendsOnly, // Shared with all friends
  public, // Publicly discoverable
}

enum JoinApproval { owner, members }

/// Enum for itinerary item types.
enum ItineraryItemType {
  flight,
  stay,
  lodging,
  food,
  activity,
  transport,
  note,
  other,
}

enum ItineraryStatus { planned, booked, done }

ItineraryStatus _statusFromData(String? value, bool isCompleted) {
  if (value != null) {
    return ItineraryStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ItineraryStatus.planned,
    );
  }
  return isCompleted ? ItineraryStatus.done : ItineraryStatus.planned;
}

enum StoryMomentType { text, photo }

enum TripUpdateKind { system, planner, people, story, chat }

enum JoinRequestStatus { pending, approved, declined }

/// Enum for member roles in a trip.
enum MemberRole {
  owner, // Created and owns the trip
  collaborator, // Can view and edit
  viewer, // Read-only access
}
