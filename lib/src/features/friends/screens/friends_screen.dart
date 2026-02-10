import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/models/friends.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/widgets/empty_state_card.dart';
import 'package:flutter_application_trial/src/widgets/primary_button.dart';
import 'package:flutter_application_trial/src/widgets/async_state_view.dart';
import 'package:intl/intl.dart';

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  DateTime? _lastRequestAt;
  final Map<String, DateTime> _lastRequestByUser = {};

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _focusSearch() {
    _searchFocusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(authSessionProvider).value?.userId ?? '';
    final friendsAsync = ref.watch(friendsProvider);
    final incomingAsync = ref.watch(incomingFriendRequestsProvider);
    final outgoingAsync = ref.watch(outgoingFriendRequestsProvider);
    final blockedAsync = ref.watch(blockedUsersProvider);
    final tripsAsync = ref.watch(userTripsStreamProvider);

    final friends = friendsAsync.value ?? const <Friendship>[];
    final incoming = incomingAsync.value ?? const <FriendRequest>[];
    final outgoing = outgoingAsync.value ?? const <FriendRequest>[];
    final blocked = blockedAsync.value ?? const <BlockedUser>[];
    final trips = tripsAsync.value ?? const <Trip>[];

    final blockedIds = blocked.map((entry) => entry.blockedUserId).toSet();
    final friendIds = friends
        .map((friendship) => friendship.otherUserId(currentUserId))
        .where((id) => id.isNotEmpty)
        .toSet();
    final incomingIds = incoming.map((req) => req.fromUserId).toSet();
    final outgoingIds = outgoing.map((req) => req.toUserId).toSet();

    final profileIds = {...friendIds, ...incomingIds, ...outgoingIds};
    final profilesAsync = ref.watch(
      userProfilesProvider(profileIds.toList(growable: false)),
    );
    final profiles = profilesAsync.value ?? <String, UserProfile?>{};

    return Column(
      children: [
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: _FriendsSearchBar(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (value) => setState(() => _searchQuery = value),
            onClear: () => setState(() {
              _searchController.clear();
              _searchQuery = '';
            }),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(AppRadii.lg),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: AppColors.text,
                      unselectedLabelColor: AppColors.mutedText,
                      indicator: BoxDecoration(
                          color: AppColors.primarySoft,
                        borderRadius: BorderRadius.circular(AppRadii.lg),
                      ),
                      labelStyle: Theme.of(context).textTheme.labelSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                      tabs: [
                        const Tab(
                          child: Text(
                            'Friends',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Tab(
                          child: Text(
                            incoming.isNotEmpty
                                ? 'Requests (${incoming.length})'
                                : 'Requests',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildFriendsTab(
                        context: context,
                        currentUserId: currentUserId,
                        friends: friends,
                        incoming: incoming,
                        outgoing: outgoing,
                        blockedIds: blockedIds,
                        profiles: profiles,
                        trips: trips,
                      ),
                      _buildRequestsTab(
                        context: context,
                        currentUserId: currentUserId,
                        incoming: incoming,
                        outgoing: outgoing,
                        profiles: profiles,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFriendsTab({
    required BuildContext context,
    required String currentUserId,
    required List<Friendship> friends,
    required List<FriendRequest> incoming,
    required List<FriendRequest> outgoing,
    required Set<String> blockedIds,
    required Map<String, UserProfile?> profiles,
    required List<Trip> trips,
  }) {
    final repo = ref.read(repositoryProvider);
    final friendIds = friends
        .map((friendship) => friendship.otherUserId(currentUserId))
        .where((id) => id.isNotEmpty)
        .toList();

    final hasQuery = _searchQuery.trim().length >= 2;
    final searchAsync = hasQuery
        ? ref.watch(friendSearchProvider(_searchQuery))
        : null;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        if (hasQuery)
          _buildSearchSection(
            context: context,
            repo: repo,
            currentUserId: currentUserId,
            searchAsync: searchAsync!,
            friends: friends,
            incoming: incoming,
            outgoing: outgoing,
            blockedIds: blockedIds,
            trips: trips,
          )
        else ...[
          if (friends.isEmpty)
            EmptyStateCard(
              title: 'No friends yet',
              subtitle: 'Search by username, email, or phone to add friends.',
              icon: Icons.group_outlined,
              actionLabel: 'Find friends',
              onAction: _focusSearch,
            )
          else
            ...friendIds.map((friendId) {
              final profile = profiles[friendId];
              if (profile == null) {
                return const _FriendCardPlaceholder();
              }
              final mutualCount = _mutualTripCount(
                trips,
                currentUserId,
                friendId,
              );
              final lastTrip = _lastMutualTrip(trips, currentUserId, friendId);
              final subtitle = _friendSubtitle(profile, mutualCount, lastTrip);

              return _FriendCard(
                profile: profile,
                subtitle: subtitle,
                mutualTripsCount: mutualCount,
                onInvite: () =>
                    _openTripPicker(context, profile, trips, currentUserId),
                onRemove: () => repo.removeFriend(profile.userId),
                onBlock: () => repo.blockUser(profile.userId),
              );
            }),
          const SizedBox(height: 16),
          _buildSuggestedSection(
            context: context,
            repo: repo,
            currentUserId: currentUserId,
            friends: friends,
            incoming: incoming,
            outgoing: outgoing,
            blockedIds: blockedIds,
            trips: trips,
          ),
        ],
      ],
    );
  }

  Widget _buildSearchSection({
    required BuildContext context,
    required TripRepository repo,
    required String currentUserId,
    required AsyncValue<List<UserProfile>> searchAsync,
    required List<Friendship> friends,
    required List<FriendRequest> incoming,
    required List<FriendRequest> outgoing,
    required Set<String> blockedIds,
    required List<Trip> trips,
  }) {
    return searchAsync.when(
      data: (results) {
        final friendIds = friends
            .map((friendship) => friendship.otherUserId(currentUserId))
            .where((id) => id.isNotEmpty)
            .toSet();
        final incomingIds = incoming.map((req) => req.fromUserId).toSet();
        final outgoingIds = outgoing.map((req) => req.toUserId).toSet();
        final visible = results
            .where((profile) => !blockedIds.contains(profile.userId))
            .toList();

        if (visible.isEmpty) {
          return EmptyStateCard(
            title: 'No matches yet',
            subtitle: 'Try searching by email, phone, or handle.',
            icon: Icons.search_off_outlined,
            actionLabel: 'Edit search',
            onAction: _focusSearch,
          );
        }

        return Column(
          children: visible.map((profile) {
            final mutualCount = _mutualTripCount(
              trips,
              currentUserId,
              profile.userId,
            );
            final lastTrip = _lastMutualTrip(
              trips,
              currentUserId,
              profile.userId,
            );
            final subtitle = _friendSubtitle(profile, mutualCount, lastTrip);
            final isFriend = friendIds.contains(profile.userId);
            final isIncoming = incomingIds.contains(profile.userId);
            final isOutgoing = outgoingIds.contains(profile.userId);

            return _FriendCard(
              profile: profile,
              subtitle: subtitle,
              mutualTripsCount: mutualCount,
              action: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isFriend)
                    _StatusPill(label: 'Friends')
                  else if (isIncoming)
                    _FriendActionButton(
                      label: 'Accept',
                      onPressed: () => repo.respondToFriendRequest(
                        incoming
                            .firstWhere(
                              (req) => req.fromUserId == profile.userId,
                            )
                            .id,
                        FriendRequestStatus.accepted,
                      ),
                    )
                  else if (isOutgoing)
                    _StatusPill(label: 'Pending')
                  else
                    _FriendActionButton(
                      label: 'Add',
                      onPressed: () => _sendFriendRequest(repo, profile.userId),
                    ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: 'Block user',
                    icon: const Icon(Icons.block_outlined),
                    onPressed: () => repo.blockUser(profile.userId),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      },
      loading: () => const AsyncLoadingView.list(
        itemCount: 3,
        itemHeight: 88,
      ),
      error: (e, st) => AsyncErrorView(
        message: 'We could not load results. Try again in a moment.',
        onRetry: () => ref.invalidate(friendSearchProvider(_searchQuery)),
      ),
    );
  }

  Widget _buildSuggestedSection({
    required BuildContext context,
    required TripRepository repo,
    required String currentUserId,
    required List<Friendship> friends,
    required List<FriendRequest> incoming,
    required List<FriendRequest> outgoing,
    required Set<String> blockedIds,
    required List<Trip> trips,
  }) {
    if (trips.isEmpty) return const SizedBox.shrink();
    final friendIds = friends
        .map((friendship) => friendship.otherUserId(currentUserId))
        .where((id) => id.isNotEmpty)
        .toSet();
    final incomingIds = incoming.map((req) => req.fromUserId).toSet();
    final outgoingIds = outgoing.map((req) => req.toUserId).toSet();

    final candidateIds = <String>{};
    for (final trip in trips) {
      for (final member in trip.members) {
        if (member.userId == currentUserId) continue;
        candidateIds.add(member.userId);
      }
    }

    final suggestions = candidateIds
        .where(
          (id) =>
              !friendIds.contains(id) &&
              !incomingIds.contains(id) &&
              !outgoingIds.contains(id) &&
              !blockedIds.contains(id),
        )
        .toList();

    if (suggestions.isEmpty) return const SizedBox.shrink();
    final profilesAsync = ref.watch(
      userProfilesProvider(suggestions.toList(growable: false)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suggested from your trips',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        profilesAsync.when(
          data: (profiles) {
            final items = profiles.values.whereType<UserProfile>().toList();
            return Column(
              children: items.map((profile) {
                final mutualCount = _mutualTripCount(
                  trips,
                  currentUserId,
                  profile.userId,
                );
                final lastTrip = _lastMutualTrip(
                  trips,
                  currentUserId,
                  profile.userId,
                );
                final subtitle = _friendSubtitle(
                  profile,
                  mutualCount,
                  lastTrip,
                );
                return _FriendCard(
                  profile: profile,
                  subtitle: subtitle,
                  mutualTripsCount: mutualCount,
                  action: _FriendActionButton(
                    label: 'Add',
                    onPressed: () => _sendFriendRequest(repo, profile.userId),
                  ),
                );
              }).toList(),
            );
          },
          loading: () => const AsyncLoadingView.list(
            itemCount: 2,
            itemHeight: 88,
          ),
          error: (e, st) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildRequestsTab({
    required BuildContext context,
    required String currentUserId,
    required List<FriendRequest> incoming,
    required List<FriendRequest> outgoing,
    required Map<String, UserProfile?> profiles,
  }) {
    final repo = ref.read(repositoryProvider);

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        Text(
          'Pending requests',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (incoming.isEmpty && outgoing.isEmpty)
          EmptyStateCard(
            title: 'No pending requests',
            subtitle: 'Friend requests will show up here.',
            icon: Icons.mail_outline,
            actionLabel: 'Search friends',
            onAction: _focusSearch,
          )
        else ...[
          if (incoming.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Incoming',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: AppColors.mutedText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                ...incoming.map((request) {
                  final profile = profiles[request.fromUserId];
                  if (profile == null) return const _FriendCardPlaceholder();
                  return _FriendCard(
                    profile: profile,
                    subtitle: 'Wants to connect with you',
                    mutualTripsCount: 0,
                    action: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _FriendActionButton(
                          label: 'Accept',
                          onPressed: () => repo.respondToFriendRequest(
                            request.id,
                            FriendRequestStatus.accepted,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () => repo.respondToFriendRequest(
                            request.id,
                            FriendRequestStatus.declined,
                          ),
                          child: const Text('Decline'),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          if (outgoing.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Outgoing',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.mutedText,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            ...outgoing.map((request) {
              final profile = profiles[request.toUserId];
              if (profile == null) return const _FriendCardPlaceholder();
              return _FriendCard(
                profile: profile,
                subtitle: 'Request sent',
                mutualTripsCount: 0,
                action: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _StatusPill(label: 'Pending'),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => repo.cancelFriendRequest(request.id),
                      child: const Text('Cancel'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ],
    );
  }

  void _sendFriendRequest(TripRepository repo, String userId) {
    final now = DateTime.now();
    final lastGlobal = _lastRequestAt;
    final lastForUser = _lastRequestByUser[userId];

    if (lastGlobal != null && now.difference(lastGlobal).inSeconds < 12) {
      _showSnack('Slow down for a moment before sending again.');
      return;
    }
    if (lastForUser != null && now.difference(lastForUser).inSeconds < 60) {
      _showSnack('You already sent a request recently.');
      return;
    }

    _lastRequestAt = now;
    _lastRequestByUser[userId] = now;
    repo.sendFriendRequest(userId);
  }

  void _showSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openTripPicker(
    BuildContext context,
    UserProfile profile,
    List<Trip> trips,
    String currentUserId,
  ) async {
    if (trips.isEmpty) {
      _showSnack('Create a trip before inviting friends.');
      return;
    }

    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadii.lg)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite to a trip',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: trips.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final trip = trips[index];
                      final isMember = trip.members.any(
                        (member) => member.userId == profile.userId,
                      );
                      return Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(AppRadii.md),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    trip.destination,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    _formatDateRange(
                                      trip.startDate,
                                      trip.endDate,
                                    ),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(color: AppColors.mutedText),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            PrimaryButton(
                              label: isMember ? 'Added' : 'Invite',
                              isCompact: true,
                              onPressed: isMember
                                  ? null
                                  : () {
                                      final repo = ref.read(repositoryProvider);
                                      repo.addMember(
                                        trip.id,
                                        Member(
                                          userId: profile.userId,
                                          name: profile.displayName,
                                          email: profile.email,
                                          avatarUrl: profile.photoUrl,
                                          role: MemberRole.collaborator,
                                          joinedAt: DateTime.now(),
                                        ),
                                      );
                                      Navigator.of(sheetContext).pop();
                                    },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  int _mutualTripCount(List<Trip> trips, String me, String friendId) {
    return trips
        .where(
          (trip) =>
              trip.members.any((member) => member.userId == me) &&
              trip.members.any((member) => member.userId == friendId),
        )
        .length;
  }

  Trip? _lastMutualTrip(List<Trip> trips, String me, String friendId) {
    final mutual = trips
        .where(
          (trip) =>
              trip.members.any((member) => member.userId == me) &&
              trip.members.any((member) => member.userId == friendId),
        )
        .toList();
    if (mutual.isEmpty) return null;
    mutual.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return mutual.first;
  }

  String _friendSubtitle(UserProfile profile, int mutualCount, Trip? lastTrip) {
    final handle = profile.handle != null && profile.handle!.isNotEmpty
        ? '@${profile.handle}'
        : null;
    final identity =
        handle ?? profile.email ?? profile.phone ?? 'No handle provided';
    if (mutualCount == 0 || lastTrip == null) {
      return '$identity · $mutualCount mutual trips';
    }
    final recent = _relativeTime(lastTrip.updatedAt);
    return '$identity · $mutualCount mutual trips · ${lastTrip.destination} · $recent';
  }

  String _relativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final diff = now.difference(dateTime);
    if (diff.inMinutes < 2) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final weeks = (diff.inDays / 7).floor();
    if (weeks < 5) return '${weeks}w ago';
    final months = (diff.inDays / 30).floor();
    if (months < 12) return '${months}mo ago';
    final years = (diff.inDays / 365).floor();
    return '${years}y ago';
  }

  String _formatDateRange(DateTime start, DateTime end) {
    final formatter = DateFormat('MMM d');
    final sameMonth = start.month == end.month && start.year == end.year;
    if (sameMonth) {
      return '${formatter.format(start)} - ${end.day}, ${end.year}';
    }
    return '${formatter.format(start)} - ${formatter.format(end)}, ${end.year}';
  }
}

class _FriendsSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  const _FriendsSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: 'Search by username, email, or phone',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(icon: const Icon(Icons.close), onPressed: onClear),
      ),
    );
  }
}

class _FriendCard extends StatelessWidget {
  final UserProfile profile;
  final String subtitle;
  final int mutualTripsCount;
  final VoidCallback? onInvite;
  final VoidCallback? onRemove;
  final VoidCallback? onBlock;
  final Widget? action;

  const _FriendCard({
    required this.profile,
    required this.subtitle,
    required this.mutualTripsCount,
    this.onInvite,
    this.onRemove,
    this.onBlock,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundImage: profile.photoUrl != null
                ? NetworkImage(profile.photoUrl!)
                : null,
            child: profile.photoUrl == null
                ? Text(
                    profile.displayName.isEmpty
                        ? '?'
                        : profile.displayName[0].toUpperCase(),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          if (action != null)
            action!
          else
            PopupMenuButton<String>(
              onSelected: (value) {
                if (value == 'invite') onInvite?.call();
                if (value == 'remove') onRemove?.call();
                if (value == 'block') onBlock?.call();
              },
              itemBuilder: (context) => [
                if (onInvite != null)
                  const PopupMenuItem(
                    value: 'invite',
                    child: Text('Invite to trip'),
                  ),
                if (onRemove != null)
                  const PopupMenuItem(
                    value: 'remove',
                    child: Text('Remove friend'),
                  ),
                if (onBlock != null)
                  const PopupMenuItem(
                    value: 'block',
                    child: Text('Block user'),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _FriendCardPlaceholder extends StatelessWidget {
  const _FriendCardPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.placeholder,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 120,
                  decoration: BoxDecoration(
                    color: AppColors.placeholder,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 180,
                  decoration: BoxDecoration(
                    color: AppColors.placeholderAlt,
                    borderRadius: BorderRadius.circular(AppRadii.sm),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FriendActionButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _FriendActionButton({required this.label, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
      child: Text(label),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
