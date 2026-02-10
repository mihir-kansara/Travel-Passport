import 'package:cloud_firestore/cloud_firestore.dart';

DateTime _parseTimestamp(dynamic value) {
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

enum FriendRequestStatus { pending, accepted, declined, canceled }

class FriendRequest {
  final String id;
  final String fromUserId;
  final String toUserId;
  final FriendRequestStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  FriendRequest({
    required this.id,
    required this.fromUserId,
    required this.toUserId,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  FriendRequest copyWith({
    String? id,
    String? fromUserId,
    String? toUserId,
    FriendRequestStatus? status,
    DateTime? createdAt,
    DateTime? respondedAt,
  }) {
    return FriendRequest(
      id: id ?? this.id,
      fromUserId: fromUserId ?? this.fromUserId,
      toUserId: toUserId ?? this.toUserId,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      respondedAt: respondedAt ?? this.respondedAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'fromUserId': fromUserId,
      'toUserId': toUserId,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      if (respondedAt != null) 'respondedAt': Timestamp.fromDate(respondedAt!),
    };
  }

  factory FriendRequest.fromFirestore(Map<String, dynamic> data) {
    return FriendRequest(
      id: data['id'] as String? ?? '',
      fromUserId: data['fromUserId'] as String? ?? '',
      toUserId: data['toUserId'] as String? ?? '',
      status: FriendRequestStatus.values.firstWhere(
        (value) => value.name == (data['status'] as String?),
        orElse: () => FriendRequestStatus.pending,
      ),
      createdAt: _parseTimestamp(data['createdAt']),
      respondedAt: data['respondedAt'] == null
          ? null
          : _parseTimestamp(data['respondedAt']),
    );
  }
}

class Friendship {
  final String id;
  final List<String> userIds;
  final DateTime createdAt;
  final DateTime? lastInteractionAt;

  Friendship({
    required this.id,
    required this.userIds,
    required this.createdAt,
    this.lastInteractionAt,
  });

  String otherUserId(String currentUserId) {
    return userIds.firstWhere((id) => id != currentUserId, orElse: () => '');
  }

  Friendship copyWith({
    String? id,
    List<String>? userIds,
    DateTime? createdAt,
    DateTime? lastInteractionAt,
  }) {
    return Friendship(
      id: id ?? this.id,
      userIds: userIds ?? this.userIds,
      createdAt: createdAt ?? this.createdAt,
      lastInteractionAt: lastInteractionAt ?? this.lastInteractionAt,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'userIds': userIds,
      'createdAt': Timestamp.fromDate(createdAt),
      if (lastInteractionAt != null)
        'lastInteractionAt': Timestamp.fromDate(lastInteractionAt!),
    };
  }

  factory Friendship.fromFirestore(Map<String, dynamic> data) {
    return Friendship(
      id: data['id'] as String? ?? '',
      userIds: (data['userIds'] as List?)?.cast<String>() ?? const [],
      createdAt: _parseTimestamp(data['createdAt']),
      lastInteractionAt: data['lastInteractionAt'] == null
          ? null
          : _parseTimestamp(data['lastInteractionAt']),
    );
  }
}

class BlockedUser {
  final String id;
  final String blockerId;
  final String blockedUserId;
  final DateTime createdAt;

  BlockedUser({
    required this.id,
    required this.blockerId,
    required this.blockedUserId,
    required this.createdAt,
  });

  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'blockerId': blockerId,
      'blockedUserId': blockedUserId,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory BlockedUser.fromFirestore(Map<String, dynamic> data) {
    return BlockedUser(
      id: data['id'] as String? ?? '',
      blockerId: data['blockerId'] as String? ?? '',
      blockedUserId: data['blockedUserId'] as String? ?? '',
      createdAt: _parseTimestamp(data['createdAt']),
    );
  }
}
