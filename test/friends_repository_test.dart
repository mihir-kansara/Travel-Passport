import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_application_trial/src/repositories/mock_repository.dart';
import 'package:flutter_application_trial/src/models/friends.dart';

void main() {
  group('MockTripRepository friends', () {
    test('accepting incoming request creates friendship', () async {
      final repo = MockTripRepository(currentUserId: 'user_1');

      final incoming = await repo.watchIncomingFriendRequests().first;
      expect(incoming, isNotEmpty);
      final request = incoming.first;

      await repo.respondToFriendRequest(
        request.id,
        FriendRequestStatus.accepted,
      );

      final friends = await repo.watchFriends().first;
      expect(
        friends.any((friendship) =>
            friendship.userIds.contains(request.fromUserId)),
        isTrue,
      );
    });

    test('blocking removes pending and friendship', () async {
      final repo = MockTripRepository(currentUserId: 'user_1');

      await repo.sendFriendRequest('user_5');
      var outgoing = await repo.watchOutgoingFriendRequests().first;
      expect(outgoing.any((req) => req.toUserId == 'user_5'), isTrue);

      await repo.blockUser('user_5');
      outgoing = await repo.watchOutgoingFriendRequests().first;
      expect(outgoing.any((req) => req.toUserId == 'user_5'), isFalse);

      final friends = await repo.watchFriends().first;
      expect(
        friends.any((friendship) => friendship.userIds.contains('user_5')),
        isFalse,
      );
    });

    test('search returns matches by handle and email', () async {
      final repo = MockTripRepository(currentUserId: 'user_1');

      final handleMatches = await repo.searchUserProfiles('janesmith');
      expect(handleMatches.any((profile) => profile.userId == 'user_2'), isTrue);

      final emailMatches = await repo.searchUserProfiles('luca@example.com');
      expect(emailMatches.any((profile) => profile.userId == 'user_6'), isTrue);
    });
  });
}
