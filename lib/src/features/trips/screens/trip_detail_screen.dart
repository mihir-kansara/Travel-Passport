import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_application_trial/src/app_config.dart';
import 'package:flutter_application_trial/src/models/friends.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/features/trips/checklist_templates.dart';
import 'package:flutter_application_trial/src/features/trips/screens/trip_settings_screen.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/widgets/info_chip.dart';

enum TripDetailTab { planner, checklist, story, people, chat }

extension TripDetailTabQuery on TripDetailTab {
  String toQueryValue() {
    switch (this) {
      case TripDetailTab.planner:
        return 'planner';
      case TripDetailTab.checklist:
        return 'checklist';
      case TripDetailTab.story:
        return 'story';
      case TripDetailTab.people:
        return 'people';
      case TripDetailTab.chat:
        return 'chat';
    }
  }
}

TripDetailTab tripDetailTabFromQuery(String? tabName) {
  switch (tabName) {
    case 'planner':
      return TripDetailTab.planner;
    case 'checklist':
      return TripDetailTab.checklist;
    case 'story':
      return TripDetailTab.story;
    case 'people':
      return TripDetailTab.people;
    case 'chat':
      return TripDetailTab.chat;
    default:
      return TripDetailTab.planner;
  }
}

enum TripPermission { edit, post, invite, managePeople, changePrivacy }

enum TripPrivacyOption { privateLink, friendsOnly, public }

class TripDetailScreen extends ConsumerStatefulWidget {
  final String tripId;
  final TripDetailTab initialTab;

  const TripDetailScreen({
    super.key,
    required this.tripId,
    this.initialTab = TripDetailTab.planner,
  });

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {
  int _selectedDayIndex = 0;
  final TextEditingController _commentController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  bool _inviteLoading = false;
  String? _inviteLink;
  String? _inviteError;
  Invite? _lastInvite;
  MemberRole _inviteRole = MemberRole.viewer;
  final TextEditingController _inviteMessageController =
      TextEditingController();
  final Set<String> _busyActions = {};
  final Map<String, bool> _likeOverrides = {};
  final List<_PendingChatEntry> _pendingChats = [];
  final List<ChatMessage> _olderChatMessages = [];
  bool _isLoadingOlderChats = false;
  bool _hasMoreChats = true;

  @override
  void dispose() {
    _commentController.dispose();
    _chatController.dispose();
    _inviteMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {

    final tripAsync = ref.watch(tripByIdProvider(widget.tripId));
    final itineraryAsync = ref.watch(
      tripItineraryStreamProvider(widget.tripId),
    );
    final categoriesAsync = ref.watch(itineraryCategoriesProvider);
    final commentsAsync = ref.watch(tripCommentsStreamProvider(widget.tripId));
    final chatAsync = ref.watch(tripChatStreamProvider(widget.tripId));
    final currentUserId = ref.watch(authSessionProvider).value?.userId ?? '';

    return AppScaffold(
      title: 'Trip details',
      onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      actions: [
        IconButton(
          tooltip: 'Trip settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _openSettings(),
        ),
      ],
      padding: EdgeInsets.zero,
      body: tripAsync.when(
        data: (trip) {
          if (trip == null) {
            return const Center(child: Text('Trip not found'));
          }
          final profileIds = <String>{
            ...trip.members.map((m) => m.userId),
            ...trip.joinRequests.map((r) => r.userId),
          };
          final profilesAsync = ref.watch(
            userProfilesProvider(profileIds.toList(growable: false)),
          );
          final profiles = profilesAsync.value ?? <String, UserProfile?>{};
          final categories = categoriesAsync.value ?? const <ItineraryCategory>[];
          final currentRole = _roleForUser(trip, currentUserId);
          final canEdit = _hasPermission(currentRole, TripPermission.edit);
          final canPost = _hasPermission(currentRole, TripPermission.post);
          final canInvite = _hasPermission(currentRole, TripPermission.invite);
          final canManagePeople =
              _hasPermission(currentRole, TripPermission.managePeople);
          final canChangePrivacy =
              _hasPermission(currentRole, TripPermission.changePrivacy);

          return DefaultTabController(
            length: 5,
            initialIndex: widget.initialTab.index,
            child: Column(
              children: [
                _TripHeader(trip: trip),
                _TripTabs(),
                Expanded(
                  child: TabBarView(
                    children: [
                      itineraryAsync.when(
                        data: (items) => _PlannerTab(
                          trip: trip,
                          items: items,
                          categories: categories,
                          profiles: profiles,
                          selectedDayIndex: _selectedDayIndex,
                          onSelectDay: (index) =>
                              setState(() => _selectedDayIndex = index),
                          canEdit: canEdit,
                          onRequestUpgrade: () =>
                              _showUpgradeDialog(trip, TripPermission.edit),
                          onAddItem: (section) => _openPlannerSheet(
                            trip,
                            items,
                            categories: categories,
                            section: section,
                          ),
                          onEditItem: (item) => _openPlannerSheet(
                            trip,
                            items,
                            categories: categories,
                            item: item,
                          ),
                          onEditNotes: (item) => _openNotesEditor(trip, item),
                          onDeleteItem: (item) => _handleDeleteItem(trip, item),
                          onToggleStatus: (item) =>
                              _handleToggleStatus(trip, item),
                          onOpenComments: (item) => _openItineraryComments(
                            trip,
                            item,
                            profiles,
                            canPost,
                          ),
                          onReorderDay: (items) =>
                              _handleReorderDay(trip, items),
                        ),
                        loading: () => const _PlannerLoading(),
                        error: (e, st) => _AsyncErrorState(
                          message: 'Unable to load the itinerary.',
                          onRetry: () => ref.refresh(
                            tripItineraryStreamProvider(widget.tripId),
                          ),
                        ),
                      ),
                      _ChecklistTab(
                        trip: trip,
                        profiles: profiles,
                        currentUserId: currentUserId,
                        canEditShared: canEdit,
                        onRequestUpgrade: () =>
                            _showUpgradeDialog(trip, TripPermission.edit),
                        onUpsertShared: _upsertSharedChecklistItem,
                        onDeleteShared: _deleteSharedChecklistItem,
                        onUpsertPersonal: _upsertPersonalChecklistItem,
                        onDeletePersonal: _deletePersonalChecklistItem,
                        onSetPersonalVisibility: _setPersonalChecklistVisibility,
                      ),
                      _StoryTab(
                        trip: trip,
                        profiles: profiles,
                        comments: commentsAsync.value ?? const [],
                        commentController: _commentController,
                        onSendComment: () => _handleSendComment(trip),
                        onRequestUpgrade: () =>
                            _showUpgradeDialog(trip, TripPermission.post),
                        canPost: canPost,
                        onTogglePublish: (value) =>
                            _handlePublishToggle(trip, value),
                        onToggleMoment: (moment) =>
                            _handleToggleMoment(trip, moment),
                        isSendingComment: _isBusy('comment-${trip.id}'),
                        isPublishing: _isBusy('publish-${trip.id}'),
                        likeCount: _likeCountForTrip(trip, currentUserId),
                      ),
                      _PeopleTab(
                        trip: trip,
                        profiles: profiles,
                        onRequestJoin: () => _handleJoinRequest(trip),
                        onRespondJoin: (requestId, status) =>
                            _handleJoinRespond(trip, requestId, status),
                        currentUserId: currentUserId,
                        onAddFromFriends: () => _openFriendsPicker(trip),
                        onInvite: () => _openInviteSheet(trip),
                        onUpdateRole: (userId, role) =>
                            _handleUpdateRole(trip, userId, role),
                        onRemoveMember: (userId) =>
                            _handleRemoveMember(trip, userId),
                        onLeaveTrip: () => _handleLeaveTrip(trip),
                        onRequestUpgrade: () =>
                            _showUpgradeDialog(trip, TripPermission.invite),
                        onUpdatePrivacy: (option) =>
                            _handlePrivacyUpdate(trip, option),
                        canInvite: canInvite,
                        canManagePeople: canManagePeople,
                        canChangePrivacy: canChangePrivacy,
                        inviteLink: _inviteLink,
                        isJoinRequestBusy: _isBusy('join-request-${trip.id}'),
                        isResponding: (requestId) =>
                            _isBusy('join-respond-$requestId'),
                      ),
                      _ChatTab(
                        trip: trip,
                        profiles: profiles,
                        messages: _mergeChatMessages(
                          chatAsync.value ?? const [],
                        ),
                        chatController: _chatController,
                        onSend: () => _handleSendChat(trip),
                        currentUserId: currentUserId,
                        canPost: canPost,
                        onRequestUpgrade: () =>
                            _showUpgradeDialog(trip, TripPermission.post),
                        isSending: _isBusy('chat-${trip.id}'),
                        pendingMessages: _pendingChats,
                        canLoadMore: _hasMoreChats,
                        isLoadingMore: _isLoadingOlderChats,
                        onLoadMore: () => _loadOlderChats(
                          trip.id,
                          _mergeChatMessages(
                            chatAsync.value ?? const [],
                          ),
                        ),
                        onRetry: (entry) => _sendChatMessage(
                          trip,
                          text: entry.message.text,
                          pending: entry,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const _TripDetailLoading(),
        error: (e, st) => _AsyncErrorState(
          message: 'Unable to load this trip.',
          onRetry: () => ref.refresh(tripByIdProvider(widget.tripId)),
        ),
      ),
    );
  }

  bool _isBusy(String key) => _busyActions.contains(key);

  Member? _memberForUser(Trip trip, String userId) {
    if (userId.isEmpty) return null;
    try {
      return trip.members.firstWhere((m) => m.userId == userId);
    } catch (_) {
      return null;
    }
  }

  MemberRole? _roleForUser(Trip trip, String userId) {
    return _memberForUser(trip, userId)?.role;
  }

  bool _hasPermission(MemberRole? role, TripPermission permission) {
    if (role == null) return false;
    switch (permission) {
      case TripPermission.edit:
      case TripPermission.post:
      case TripPermission.invite:
        return role == MemberRole.owner || role == MemberRole.collaborator;
      case TripPermission.managePeople:
      case TripPermission.changePrivacy:
        return role == MemberRole.owner;
    }
  }

  String _permissionTitle(TripPermission permission) {
    switch (permission) {
      case TripPermission.edit:
        return 'Edit access needed';
      case TripPermission.post:
        return 'Posting access needed';
      case TripPermission.invite:
        return 'Invite access needed';
      case TripPermission.managePeople:
        return 'Host access needed';
      case TripPermission.changePrivacy:
        return 'Host access needed';
    }
  }

  String _permissionMessage(TripPermission permission) {
    switch (permission) {
      case TripPermission.edit:
        return 'Ask the owner to unlock itinerary edits for you.';
      case TripPermission.post:
        return 'Ask the owner to unlock posting and story updates.';
      case TripPermission.invite:
        return 'Only the owner and admins can invite travelers.';
      case TripPermission.managePeople:
        return 'Only the owner can manage roles and removals.';
      case TripPermission.changePrivacy:
        return 'Only the owner can change trip privacy.';
    }
  }

  String _upgradeNote(TripPermission permission) {
    switch (permission) {
      case TripPermission.edit:
        return 'Requesting edit access for the itinerary.';
      case TripPermission.post:
        return 'Requesting posting access for chat and story updates.';
      case TripPermission.invite:
        return 'Requesting invite permissions for this trip.';
      case TripPermission.managePeople:
        return 'Requesting host permissions.';
      case TripPermission.changePrivacy:
        return 'Requesting permission to manage trip privacy.';
    }
  }

  Future<void> _showUpgradeDialog(
    Trip trip,
    TripPermission permission,
  ) async {
    final shouldRequest = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_permissionTitle(permission)),
        content: Text(_permissionMessage(permission)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Request upgrade'),
          ),
        ],
      ),
    );
    if (shouldRequest == true) {
      await _requestUpgrade(trip, permission);
    }
  }

  Future<void> _requestUpgrade(
    Trip trip,
    TripPermission permission,
  ) async {
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to request access.',
    );
    if (!mounted || !allowed) return;
    final session = ref.read(authSessionProvider).value;
    if (session == null) return;
    final existing = trip.joinRequests.any(
      (request) =>
          request.userId == session.userId &&
          request.status == JoinRequestStatus.pending,
    );
    if (existing) {
      showGuardedSnackBar(context, 'Upgrade request already sent.');
      return;
    }
    await _runTripAction(
      'upgrade-${trip.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        final request = JoinRequest(
          id: const Uuid().v4(),
          userId: session.userId,
          note: _upgradeNote(permission),
          status: JoinRequestStatus.pending,
          createdAt: DateTime.now(),
        );
        await repo.requestToJoin(trip.id, request);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to request access right now.',
      successMessage: 'Upgrade request sent to the owner.',
    );
  }

  Future<bool> _ensureTripPermission(
    Trip trip,
    TripPermission permission, {
    required String authMessage,
  }) async {
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: authMessage,
    );
    if (!mounted || !allowed) return false;
    final session = ref.read(authSessionProvider).value;
    if (session == null) return false;
    final role = _roleForUser(trip, session.userId);
    if (!_hasPermission(role, permission)) {
      await _showUpgradeDialog(trip, permission);
      return false;
    }
    return true;
  }

  List<ChatMessage> _mergeChatMessages(List<ChatMessage> latest) {
    final merged = <String, ChatMessage>{
      for (final message in _olderChatMessages) message.id: message,
      for (final message in latest) message.id: message,
    };
    final list = merged.values.toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> _loadOlderChats(
    String tripId,
    List<ChatMessage> current,
  ) async {
    if (_isLoadingOlderChats || !_hasMoreChats) return;
    if (current.isEmpty) return;
    setState(() => _isLoadingOlderChats = true);
    final earliest = current.first;
    final repo = ref.read(repositoryProvider);
    final page = await repo.fetchChatMessagesPage(
      tripId,
      limit: 50,
      before: ChatMessagesCursor(
        createdAt: earliest.createdAt,
        messageId: earliest.id,
      ),
    );
    if (!mounted) return;
    setState(() {
      if (page.isEmpty) {
        _hasMoreChats = false;
      } else {
        for (final message in page) {
          if (_olderChatMessages.every((m) => m.id != message.id)) {
            _olderChatMessages.add(message);
          }
        }
      }
      _isLoadingOlderChats = false;
    });
  }

  int _likeCountForTrip(Trip trip, String userId) {
    final baseLiked = trip.story.likedBy.contains(userId);
    final isLiked = _likeOverrides[trip.id] ?? baseLiked;
    var count = trip.story.wallStats.likes;
    if (isLiked && !baseLiked) count += 1;
    if (!isLiked && baseLiked) count -= 1;
    if (count < 0) count = 0;
    return count;
  }

  void _setBusy(String key, bool value) {
    if (!mounted) return;
    setState(() {
      if (value) {
        _busyActions.add(key);
      } else {
        _busyActions.remove(key);
      }
    });
  }

  Future<bool> _runTripAction(
    String key,
    Future<void> Function() task, {
    String? errorMessage,
    String? successMessage,
    String? authMessage,
  }) async {
    if (_isBusy(key)) return false;
    _setBusy(key, true);
    if (authMessage != null) {
      final allowed = await ensureSignedIn(
        context,
        ref,
        message: authMessage,
      );
      if (!mounted) return false;
      if (!allowed) {
        _setBusy(key, false);
        return false;
      }
    }
    final success = await runGuarded(
      context,
      task,
      errorMessage: errorMessage,
      successMessage: successMessage,
    );
    if (mounted) {
      _setBusy(key, false);
    }
    return success;
  }

  Future<void> _handleSendComment(Trip trip) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.post,
      authMessage: 'Sign in to comment on this story.',
    );
    if (!allowed) return;
    if (!mounted) return;
    await _runTripAction(
      'comment-${trip.id}',
      () async {
        HapticFeedback.selectionClick();
        final session = ref.read(authSessionProvider).value;
        if (session == null) return;
        final repo = ref.read(repositoryProvider);
        final comment = WallComment(
          id: const Uuid().v4(),
          authorId: session.userId,
          text: text,
          createdAt: DateTime.now(),
        );
        await repo.addWallComment(trip.id, comment);
        _commentController.clear();
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
      errorMessage: 'Unable to send comment.',
    );
  }

  Future<void> _handleSendChat(Trip trip) async {
    final text = _chatController.text.trim();
    if (text.isEmpty) return;
    await _sendChatMessage(trip, text: text);
  }

  Future<void> _sendChatMessage(
    Trip trip, {
    required String text,
    _PendingChatEntry? pending,
  }) async {
    final key = 'chat-${trip.id}';
    if (_isBusy(key)) return;
    _setBusy(key, true);
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.post,
      authMessage: 'Sign in to send a message.',
    );
    if (!mounted) return;
    if (!allowed) {
      _setBusy(key, false);
      return;
    }
    final session = ref.read(authSessionProvider).value;
    if (session == null) {
      _setBusy(key, false);
      return;
    }
    HapticFeedback.selectionClick();
    final message = pending?.message ??
        ChatMessage(
          id: const Uuid().v4(),
          authorId: session.userId,
          text: text,
          createdAt: DateTime.now(),
        );
    final localId = pending?.localId ?? 'pending-${message.id}';
    if (pending == null) {
      setState(() {
        _pendingChats.add(
          _PendingChatEntry(localId: localId, message: message),
        );
      });
      _chatController.clear();
    } else {
      setState(() {
        final index = _pendingChats.indexWhere((e) => e.localId == localId);
        if (index >= 0) {
          _pendingChats[index] =
              _pendingChats[index].copyWith(isFailed: false);
        }
      });
    }

    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.sendChatMessage(trip.id, message);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to send message.',
    );
    if (!mounted) return;
    if (success) {
      setState(() {
        _pendingChats.removeWhere((entry) => entry.localId == localId);
      });
    } else {
      setState(() {
        final index = _pendingChats.indexWhere((e) => e.localId == localId);
        if (index >= 0) {
          _pendingChats[index] =
              _pendingChats[index].copyWith(isFailed: true);
        }
      });
    }
    _setBusy(key, false);
  }

  Future<bool> _upsertSharedChecklistItem(Trip trip, ChecklistItem item) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.edit,
      authMessage: 'Sign in to update shared checklist items.',
    );
    if (!allowed) return false;
    return _runTripAction(
      'checklist-shared-${item.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.upsertSharedChecklistItem(trip.id, item);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to update shared checklist.',
    );
  }

  Future<bool> _deleteSharedChecklistItem(Trip trip, String itemId) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.edit,
      authMessage: 'Sign in to update shared checklist items.',
    );
    if (!allowed) return false;
    return _runTripAction(
      'checklist-shared-delete-$itemId',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.deleteSharedChecklistItem(trip.id, itemId);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to delete shared checklist item.',
    );
  }

  Future<bool> _upsertPersonalChecklistItem(
    Trip trip,
    String ownerUserId,
    ChecklistItem item,
  ) async {
    return _runTripAction(
      'checklist-personal-$ownerUserId-${item.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.upsertPersonalChecklistItem(trip.id, ownerUserId, item);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update checklist items.',
      errorMessage: 'Unable to update checklist.',
    );
  }

  Future<bool> _deletePersonalChecklistItem(
    Trip trip,
    String ownerUserId,
    String itemId,
  ) async {
    return _runTripAction(
      'checklist-personal-delete-$ownerUserId-$itemId',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.deletePersonalChecklistItem(trip.id, ownerUserId, itemId);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update checklist items.',
      errorMessage: 'Unable to delete checklist item.',
    );
  }

  Future<bool> _setPersonalChecklistVisibility(
    Trip trip,
    String ownerUserId,
    bool isShared,
  ) async {
    return _runTripAction(
      'checklist-visibility-$ownerUserId-$isShared',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.setPersonalChecklistVisibility(
          trip.id,
          ownerUserId,
          isShared,
        );
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update checklist visibility.',
      errorMessage: 'Unable to update checklist visibility.',
    );
  }

  Future<void> _handleJoinRequest(Trip trip) async {
    await _runTripAction(
      'join-request-${trip.id}',
      () async {
        HapticFeedback.selectionClick();
        final session = ref.read(authSessionProvider).value;
        if (session == null) return;
        final repo = ref.read(repositoryProvider);
        final request = JoinRequest(
          id: const Uuid().v4(),
          userId: session.userId,
          note: 'Would love to join for a day.',
          status: JoinRequestStatus.pending,
          createdAt: DateTime.now(),
        );
        await repo.requestToJoin(trip.id, request);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to request access.',
      errorMessage: 'Unable to send join request.',
    );
  }

  Future<void> _handleJoinRespond(
    Trip trip,
    String requestId,
    JoinRequestStatus status,
  ) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.managePeople,
      authMessage: 'Sign in to manage join requests.',
    );
    if (!allowed) return;
    if (!mounted) return;
    await _runTripAction(
      'join-respond-$requestId',
      () async {
        HapticFeedback.selectionClick();
        final repo = ref.read(repositoryProvider);
        await repo.respondToJoinRequest(trip.id, requestId, status);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to update join request.',
    );
  }

  Future<void> _handleUpdateRole(
    Trip trip,
    String userId,
    MemberRole role,
  ) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.managePeople,
      authMessage: 'Sign in to manage trip members.',
    );
    if (!allowed) return;
    await _runTripAction(
      'member-role-$userId',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.updateMemberRole(trip.id, userId, role);
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
      errorMessage: 'Unable to update member role.',
    );
  }

  Future<void> _handleRemoveMember(Trip trip, String userId) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.managePeople,
      authMessage: 'Sign in to manage trip members.',
    );
    if (!allowed) return;
    await _runTripAction(
      'member-remove-$userId',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.removeMember(trip.id, userId);
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
      errorMessage: 'Unable to remove member.',
    );
  }

  Future<void> _handleLeaveTrip(Trip trip) async {
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to leave this trip.',
    );
    if (!mounted || !allowed) return;
    final session = ref.read(authSessionProvider).value;
    if (session == null) return;
    final role = _roleForUser(trip, session.userId);
    if (role == MemberRole.owner) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Owner cannot leave'),
          content: const Text(
            'Transfer ownership to another member before leaving the trip.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Leave this trip?'),
        content: const Text(
          'You will lose access to the itinerary and updates.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runTripAction(
      'leave-${trip.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.removeMember(trip.id, session.userId);
        ref.invalidate(userTripsProvider);
      },
      errorMessage: 'Unable to leave trip.',
    );
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _handlePrivacyUpdate(
    Trip trip,
    TripPrivacyOption option,
  ) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.changePrivacy,
      authMessage: 'Sign in to update trip privacy.',
    );
    if (!allowed) return;
    final updated = _applyPrivacyOption(trip, option);
    await _runTripAction(
      'privacy-${trip.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.updateTrip(updated);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to update trip privacy.',
    );
  }

  Trip _applyPrivacyOption(Trip trip, TripPrivacyOption option) {
    TripVisibility visibility;
    bool allowJoinRequests;
    switch (option) {
      case TripPrivacyOption.privateLink:
        visibility = TripVisibility.inviteOnly;
        allowJoinRequests = false;
        break;
      case TripPrivacyOption.friendsOnly:
        visibility = TripVisibility.friendsOnly;
        allowJoinRequests = true;
        break;
      case TripPrivacyOption.public:
        visibility = TripVisibility.public;
        allowJoinRequests = true;
        break;
    }
    return trip.copyWith(
      visibility: visibility,
      audience: trip.audience.copyWith(
        visibility: visibility,
        allowJoinRequests: allowJoinRequests,
      ),
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _handlePublishToggle(Trip trip, bool value) async {
    if (value) {
      final confirmed = await _showPublishPreview(trip);
      if (!confirmed) return;
    }
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.post,
      authMessage: 'Sign in to publish this story.',
    );
    if (!allowed) return;
    await _runTripAction(
      'publish-${trip.id}',
      () async {
        HapticFeedback.selectionClick();
        final repo = ref.read(repositoryProvider);
        await repo.publishToWall(trip.id, value);
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
      errorMessage: 'Unable to update story visibility.',
    );
  }

  Future<bool> _showPublishPreview(Trip trip) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview your story'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: _gradientForTrip(trip),
                image: trip.heroImageUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(trip.heroImageUrl!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              trip.story.headline.isNotEmpty
                  ? trip.story.headline
                  : '${trip.destination} passport',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              trip.story.highlights.isNotEmpty
                  ? trip.story.highlights.take(3).join(' ┬╖ ')
                  : 'Add highlights to make the story pop.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _StatusBadge(
                  label: '${trip.story.moments.length} moments',
                  tone: const Color(0xFFF1F5F9),
                ),
                _StatusBadge(
                  label: '${trip.story.photos.length} photos',
                  tone: const Color(0xFFF1F5F9),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _handleToggleMoment(Trip trip, StoryMoment moment) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.post,
      authMessage: 'Sign in to update story visibility.',
    );
    if (!allowed) return;
    await _runTripAction(
      'moment-toggle-${moment.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        final updatedMoments = trip.story.moments.map((entry) {
          if (entry.id != moment.id) return entry;
          return entry.copyWith(isPublic: !entry.isPublic);
        }).toList();
        final updatedTrip = trip.copyWith(
          story: trip.story.copyWith(moments: updatedMoments),
          updatedAt: DateTime.now(),
        );
        await repo.updateTrip(updatedTrip);
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
      errorMessage: 'Unable to update moment visibility.',
    );
  }

  Future<void> _handleToggleStatus(Trip trip, ItineraryItem item) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.edit,
      authMessage: 'Sign in to update the planner.',
    );
    if (!allowed) return;
    if (!mounted) return;
    if (!mounted) return;
    await _runTripAction(
      'planner-toggle-${item.id}',
      () async {
        HapticFeedback.selectionClick();
        final repo = ref.read(repositoryProvider);
        final newStatus = item.status == ItineraryStatus.done
            ? ItineraryStatus.planned
            : ItineraryStatus.done;
        final updated = item.copyWith(
          isCompleted: newStatus == ItineraryStatus.done,
          status: newStatus,
          updatedAt: DateTime.now(),
        );
        await repo.upsertItineraryItem(trip.id, updated);
        ref.invalidate(tripItineraryStreamProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to update itinerary item.',
    );
  }

  Future<void> _handleDeleteItem(Trip trip, ItineraryItem item) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.edit,
      authMessage: 'Sign in to update the planner.',
    );
    if (!allowed) return;
    await _runTripAction(
      'planner-delete-${item.id}',
      () async {
        HapticFeedback.selectionClick();
        final repo = ref.read(repositoryProvider);
        await repo.deleteItineraryItem(trip.id, item.id);
        ref.invalidate(tripItineraryStreamProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to delete itinerary item.',
    );
  }

  Future<void> _handleReorderDay(
    Trip trip,
    List<ItineraryItem> items,
  ) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.edit,
      authMessage: 'Sign in to update the planner.',
    );
    if (!allowed) return;
    await _runTripAction(
      'planner-reorder-${trip.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.reorderItineraryItems(trip.id, items);
        ref.invalidate(tripItineraryStreamProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to reorder itinerary items.',
    );
  }

  Future<void> _openPlannerSheet(
    Trip trip,
    List<ItineraryItem> items, {
    List<ItineraryCategory> categories = const [],
    ItinerarySection? section,
    ItineraryItem? item,
  }) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.edit,
      authMessage: 'Sign in to update the planner.',
    );
    if (!allowed) return;
    if (!mounted) return;
    final titleController = TextEditingController(text: item?.title ?? '');
    final notesController = TextEditingController(
      text: item?.notes ?? item?.description ?? '',
    );
    final locationController = TextEditingController(
      text: item?.location ?? '',
    );
    final linkController = TextEditingController(text: item?.link ?? '');
    final costController = TextEditingController(
      text: item?.cost?.toString() ?? '',
    );
    final tagsController = TextEditingController(
      text: item?.tags.join(', ') ?? '',
    );
    final photosController = TextEditingController(
      text: item?.photoUrls.join(', ') ?? '',
    );
    final date = trip.startDate.add(Duration(days: _selectedDayIndex));
    final resolvedCategories = categories.isNotEmpty
        ? categories
        : _fallbackCategories;
    final categoryById = {
      for (final entry in resolvedCategories) entry.id: entry,
    };
    ItinerarySection selectedSection =
        item?.section ?? section ?? _defaultSectionForNow();
    TimeOfDay time = item != null
        ? TimeOfDay.fromDateTime(item.dateTime)
        : _defaultTimeForSection(selectedSection);
    bool isTimeSet = item?.isTimeSet ?? false;
    var selectedCategoryId =
      item?.categoryId ?? _defaultCategoryId(resolvedCategories);
    if (!categoryById.containsKey(selectedCategoryId)) {
      selectedCategoryId = _defaultCategoryId(resolvedCategories);
    }
    ItineraryStatus selectedStatus = item?.status ?? ItineraryStatus.planned;
    String? selectedAssigneeId = item?.assigneeId ?? item?.assignedTo;
    bool showDetails = item != null;

    final result = await showModalBottomSheet<ItineraryItem>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final bottomInset = MediaQuery.of(context).viewInsets.bottom;
          return Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item == null ? 'Add to day' : 'Edit item',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Fast add with details you can fill in later.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(labelText: 'Location'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<ItinerarySection>(
                        initialValue: selectedSection,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() {
                            selectedSection = value;
                            if (!isTimeSet) {
                              time = _defaultTimeForSection(value);
                            }
                          });
                        },
                        items: ItinerarySection.values
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry,
                                child: Text(_labelForSection(entry)),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(labelText: 'Time of day'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: selectedCategoryId,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => selectedCategoryId = value);
                        },
                        items: resolvedCategories
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry.id,
                                child: Text(entry.label),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(labelText: 'Category'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Switch(
                      value: isTimeSet,
                      onChanged: (value) => setState(() => isTimeSet = value),
                      activeThumbColor: const Color(0xFF4F46E5),
                      activeTrackColor: const Color(0xFFC7D2FE),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isTimeSet ? 'Set time' : 'Anytime',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: isTimeSet
                          ? () async {
                              final picked = await showTimePicker(
                                context: context,
                                initialTime: time,
                              );
                              if (picked != null) {
                                setState(() => time = picked);
                              }
                            }
                          : null,
                      child: Text(time.format(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  key: ValueKey(selectedAssigneeId),
                  initialValue: selectedAssigneeId,
                  onChanged: (value) {
                    setState(() => selectedAssigneeId = value);
                  },
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...trip.members.map(
                      (member) => DropdownMenuItem<String?>(
                        value: member.userId,
                        child: Text(member.name),
                      ),
                    ),
                  ],
                  decoration: const InputDecoration(labelText: 'Assignee'),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<ItineraryStatus>(
                  initialValue: selectedStatus,
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => selectedStatus = value);
                  },
                  items: ItineraryStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(_labelForStatus(status)),
                        ),
                      )
                      .toList(),
                  decoration: const InputDecoration(labelText: 'Status'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => setState(() => showDetails = !showDetails),
                  child: Text(showDetails ? 'Hide details' : 'Add details'),
                ),
                if (showDetails) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    decoration: const InputDecoration(labelText: 'Notes'),
                    maxLines: 3,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: linkController,
                    decoration: const InputDecoration(labelText: 'Link'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: costController,
                    decoration: const InputDecoration(labelText: 'Cost'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tagsController,
                    decoration: const InputDecoration(
                      labelText: 'Tags (comma-separated)',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: photosController,
                    decoration: const InputDecoration(
                      labelText: 'Photo links (comma-separated)',
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () {
                          final title = titleController.text.trim();
                          if (title.isEmpty) return;
                          final dayOrders = items
                              .where(
                                (i) =>
                                    i.dateTime.year == date.year &&
                                    i.dateTime.month == date.month &&
                                    i.dateTime.day == date.day &&
                                    i.section == selectedSection,
                              )
                              .map((i) => i.order)
                              .toList();
                          final maxOrder =
                              dayOrders.isEmpty ? -1 : dayOrders.reduce(
                                (a, b) => a > b ? a : b,
                              );
                          final order = item?.order ?? maxOrder + 1;
                          final selectedTime =
                              isTimeSet ? time : _defaultTimeForSection(
                                selectedSection,
                              );
                          final dateTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            selectedTime.hour,
                            selectedTime.minute,
                          );
                          final notesText = notesController.text.trim();
                          final tagList = _parseCommaList(tagsController.text);
                          final photoList =
                              _parseCommaList(photosController.text);
                          final rawCost = costController.text.trim();
                          final cost = rawCost.isEmpty
                              ? null
                              : double.tryParse(
                                  rawCost.replaceAll(',', ''),
                                );
                          final assignee = selectedAssigneeId == null
                              ? null
                              : trip.members.firstWhere(
                                  (m) => m.userId == selectedAssigneeId,
                                  orElse: () => trip.members.first,
                                );
                          Navigator.pop(
                            context,
                            ItineraryItem(
                              id: item?.id ?? const Uuid().v4(),
                              tripId: trip.id,
                              dateTime: dateTime,
                              title: title,
                              description: notesText.isEmpty
                                  ? item?.description
                                  : null,
                              notes: notesText.isEmpty ? null : notesText,
                              type: item?.type ?? ItineraryItemType.activity,
                              section: selectedSection,
                              isTimeSet: isTimeSet,
                              categoryId: selectedCategoryId,
                              location: locationController.text.trim().isEmpty
                                  ? null
                                  : locationController.text.trim(),
                              link: linkController.text.trim().isEmpty
                                  ? null
                                  : linkController.text.trim(),
                              cost: cost,
                              tags: tagList,
                              photoUrls: photoList,
                              assignedTo: selectedAssigneeId,
                              assigneeId: selectedAssigneeId,
                              assigneeName: assignee?.name,
                              isCompleted:
                                  selectedStatus == ItineraryStatus.done,
                              status: selectedStatus,
                              order: order,
                              createdAt: item?.createdAt ?? DateTime.now(),
                              updatedAt: DateTime.now(),
                            ),
                          );
                        },
                        child: Text(item == null ? 'Add' : 'Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );

    if (result == null) return;
    await _runTripAction(
      'planner-upsert-${result.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.upsertItineraryItem(trip.id, result);
        ref.invalidate(tripItineraryStreamProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to save itinerary item.',
    );
  }

  Future<void> _openNotesEditor(Trip trip, ItineraryItem item) async {
    final allowed = await _ensureTripPermission(
      trip,
      TripPermission.edit,
      authMessage: 'Sign in to update the planner.',
    );
    if (!allowed) return;
    if (!mounted) return;
    final controller = TextEditingController(
      text: item.notes ?? item.description ?? '',
    );
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: controller,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Add a quick note'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (text == null) return;
    final updated = item.copyWith(
      notes: text.isEmpty ? null : text,
      description: text.isEmpty ? item.description : null,
      updatedAt: DateTime.now(),
    );
    await _runTripAction(
      'planner-note-${item.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.upsertItineraryItem(trip.id, updated);
        ref.invalidate(tripItineraryStreamProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      errorMessage: 'Unable to update notes.',
    );
  }

  Future<void> _openItineraryComments(
    Trip trip,
    ItineraryItem item,
    Map<String, UserProfile?> profiles,
    bool canPost,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
          child: _ItineraryCommentsSheet(
            tripId: trip.id,
            item: item,
            members: trip.members,
            profiles: profiles,
            canPost: canPost,
            onRequestUpgrade: () =>
                _showUpgradeDialog(trip, TripPermission.post),
          ),
        );
      },
    );
  }

  String _buildInviteLink(String token) {
    // TODO: Replace with Firebase Dynamic Links or short links when ready.
    return AppConfig.inviteLink(token);
  }

  Future<void> _handleCreateInvite(Trip trip, MemberRole role) async {
    if (_inviteLoading) return;
    setState(() {
      _inviteLoading = true;
      _inviteError = null;
    });
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to create an invite link.',
    );
    if (!mounted) return;
    if (!allowed) {
      if (mounted) setState(() => _inviteLoading = false);
      return;
    }
    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        final invite = await repo.createInvite(tripId: trip.id, role: role);
        final link = _buildInviteLink(invite.token);
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        setState(() {
          _inviteLink = link;
          _lastInvite = invite;
          _inviteRole = role;
        });
        showGuardedSnackBar(context, 'Invite link copied');
      },
      errorMessage: 'Unable to create invite link.',
      onError: (_) {
        if (!mounted) return;
        setState(() => _inviteError = 'Unable to create invite link.');
      },
    );
    if (mounted) {
      setState(() => _inviteLoading = false);
    }
    if (!success && mounted && _inviteError == null) {
      setState(() => _inviteError = 'Unable to create invite link.');
    }
  }

  Future<void> _handleCopyInvite() async {
    final link = _inviteLink;
    if (link == null) return;
    await runGuarded(
      context,
      () async {
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        showGuardedSnackBar(context, 'Invite link copied');
      },
      errorMessage: 'Unable to copy invite link.',
    );
  }

  Future<void> _handleShareInvite(String message) async {
    final link = _inviteLink;
    if (link == null) {
      showGuardedSnackBar(context, 'Create an invite link first.');
      return;
    }
    final trimmed = message.trim();
    final intro = trimmed.isEmpty
        ? 'Join my trip on Travel Passport.'
        : trimmed;
    await Share.share('$intro\n$link');
  }

  Future<void> _openFriendsPicker(Trip trip) async {
    final currentUserId = ref.read(authSessionProvider).value?.userId ?? '';
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        String query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Consumer(
                  builder: (context, ref, _) {
                    final friendsAsync = ref.watch(friendsProvider);
                    final blockedAsync = ref.watch(blockedUsersProvider);
                    final friends = friendsAsync.value ?? const <Friendship>[];
                    final blockedIds = blockedAsync.value
                            ?.map((entry) => entry.blockedUserId)
                            .toSet() ??
                        <String>{};
                    final friendIds = friends
                        .map((friendship) =>
                            friendship.otherUserId(currentUserId))
                        .where((id) => id.isNotEmpty)
                        .where((id) => !blockedIds.contains(id))
                        .toList();

                    if (friendIds.isEmpty) {
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Add from friends',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 12),
                          const _InlineEmptyState(
                            title: 'No friends yet',
                            subtitle:
                                'Add friends first to invite them to trips.',
                            icon: Icons.group_outlined,
                          ),
                        ],
                      );
                    }

                    final profilesAsync = ref.watch(
                      userProfilesProvider(friendIds),
                    );
                    final profiles = profilesAsync.value ??
                        <String, UserProfile?>{};
                    final filtered = profiles.values
                        .whereType<UserProfile>()
                        .where((profile) {
                          final lowered = query.trim().toLowerCase();
                          if (lowered.isEmpty) return true;
                          return profile.displayName
                                  .toLowerCase()
                                  .contains(lowered) ||
                              (profile.handle ?? '')
                                  .toLowerCase()
                                  .contains(lowered) ||
                              (profile.email ?? '')
                                  .toLowerCase()
                                  .contains(lowered);
                        })
                        .toList();

                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add from friends',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          onChanged: (value) =>
                              setModalState(() => query = value),
                          decoration: InputDecoration(
                            hintText: 'Search friends',
                            prefixIcon: const Icon(Icons.search),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Flexible(
                          child: ListView.separated(
                            shrinkWrap: true,
                            itemCount: filtered.length,
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: 8),
                            itemBuilder: (_, index) {
                              final profile = filtered[index];
                              final isMember = trip.members.any(
                                (member) => member.userId == profile.userId,
                              );
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                  border:
                                      Border.all(color: const Color(0xFFE2E8F0)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 20,
                                      backgroundImage: profile.photoUrl != null
                                          ? CachedNetworkImageProvider(
                                              profile.photoUrl!,
                                            )
                                          : null,
                                      child: profile.photoUrl == null
                                          ? Text(
                                              profile.displayName.isEmpty
                                                  ? '?'
                                                  : profile
                                                      .displayName[0]
                                                      .toUpperCase(),
                                            )
                                          : null,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            profile.displayName,
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            profile.handle != null
                                                ? '@${profile.handle}'
                                                : (profile.email ?? ''),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color:
                                                      const Color(0xFF64748B),
                                                ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    ElevatedButton(
                                      onPressed: isMember
                                          ? null
                                          : () {
                                              final repo = ref.read(
                                                repositoryProvider,
                                              );
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
                                      child: Text(isMember ? 'Added' : 'Invite'),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _openInviteSheet(Trip trip) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
          child: _InviteSheet(
            link: _inviteLink,
            error: _inviteError,
            isLoading: _inviteLoading,
            invite: _lastInvite,
            role: _inviteRole,
            messageController: _inviteMessageController,
            onRoleChanged: (role) => setState(() => _inviteRole = role),
            onCreate: () => _handleCreateInvite(trip, _inviteRole),
            onCopy: _handleCopyInvite,
            onShare: () => _handleShareInvite(_inviteMessageController.text),
            onShowQr: _inviteLink == null
                ? null
                : () => _showInviteQr(context, _inviteLink!),
          ),
        );
      },
    );
  }

  void _showInviteQr(BuildContext context, String link) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Invite QR code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: link,
                size: 200,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Scan to join this trip.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TripSettingsScreen(tripId: widget.tripId),
      ),
    );
  }
}

class _PendingChatEntry {
  final String localId;
  final ChatMessage message;
  final bool isFailed;

  const _PendingChatEntry({
    required this.localId,
    required this.message,
    this.isFailed = false,
  });

  _PendingChatEntry copyWith({bool? isFailed}) {
    return _PendingChatEntry(
      localId: localId,
      message: message,
      isFailed: isFailed ?? this.isFailed,
    );
  }
}

class _TripHeader extends StatelessWidget {
  final Trip trip;

  const _TripHeader({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        children: [
          Container(
            height: 180,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              gradient: _gradientForTrip(trip),
              image: trip.heroImageUrl != null
                  ? DecorationImage(
                      image: CachedNetworkImageProvider(trip.heroImageUrl!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
                color: Colors.black.withValues(alpha: 0.2),
              ),
              padding: const EdgeInsets.all(16),
              alignment: Alignment.bottomLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    trip.destination,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _formatDateRange(trip),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  trip.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    InfoChip(
                      icon: Icons.people_alt_outlined,
                      label: '${trip.members.length} members',
                    ),
                    InfoChip(
                      icon: Icons.shield_outlined,
                      label: _visibilityLabel(trip.audience.visibility),
                    ),
                    InfoChip(
                      icon: Icons.public,
                      label: trip.story.publishToWall ? 'On Wall' : 'Off Wall',
                      tone: trip.story.publishToWall
                          ? const Color(0xFFE0F2FE)
                          : const Color(0xFFF1F5F9),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TripTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: TabBar(
        labelColor: const Color(0xFF0F172A),
        unselectedLabelColor: const Color(0xFF94A3B8),
        indicator: BoxDecoration(
          color: const Color(0xFFE0E7FF),
          borderRadius: BorderRadius.circular(14),
        ),
        labelStyle: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
        tabs: const [
          Tab(text: 'Planner'),
          Tab(text: 'Checklist'),
          Tab(text: 'Story'),
          Tab(text: 'People'),
          Tab(text: 'Chat'),
        ],
      ),
    );
  }
}

class _PlannerTab extends StatelessWidget {
  final Trip trip;
  final List<ItineraryItem> items;
  final List<ItineraryCategory> categories;
  final Map<String, UserProfile?> profiles;
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;
  final bool canEdit;
  final VoidCallback onRequestUpgrade;
  final ValueChanged<ItinerarySection> onAddItem;
  final ValueChanged<ItineraryItem> onEditItem;
  final ValueChanged<ItineraryItem> onEditNotes;
  final ValueChanged<ItineraryItem> onDeleteItem;
  final ValueChanged<ItineraryItem> onToggleStatus;
  final ValueChanged<ItineraryItem> onOpenComments;
  final ValueChanged<List<ItineraryItem>> onReorderDay;

  const _PlannerTab({
    required this.trip,
    required this.items,
    required this.categories,
    required this.profiles,
    required this.selectedDayIndex,
    required this.onSelectDay,
    required this.canEdit,
    required this.onRequestUpgrade,
    required this.onAddItem,
    required this.onEditItem,
    required this.onEditNotes,
    required this.onDeleteItem,
    required this.onToggleStatus,
    required this.onOpenComments,
    required this.onReorderDay,
  });

  @override
  Widget build(BuildContext context) {
    final days = List.generate(
      trip.durationDays,
      (i) => trip.startDate.add(Duration(days: i)),
    );
    final grouped = _groupItemsByDay(trip, items);
    final dayItems = grouped[selectedDayIndex] ?? [];
    final dayItemsSorted = [...dayItems]..sort(_compareItineraryItems);
    final sectioned = _groupItemsBySection(dayItemsSorted);
    final progress = _completionProgress(items);
    final todayIndex = _todayIndex(trip);
    final dayLabel = DateFormat('EEE, MMM d').format(days[selectedDayIndex]);
    final canJumpToToday =
        todayIndex != null && todayIndex != selectedDayIndex;
    final updates = [...trip.updates]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final latestUpdate = updates.isEmpty ? null : updates.first;
    final updateMember = latestUpdate == null
        ? null
        : trip.members.firstWhere(
            (m) => m.userId == latestUpdate.actorId,
            orElse: () => trip.members.first,
          );
    final updateName = updateMember == null
        ? null
        : _displayNameForUser(
            userId: updateMember.userId,
            fallback: updateMember.name,
            profiles: profiles,
          );

    return Stack(
      children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Collaborative planner',
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: const Color(0xFF94A3B8),
                              ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Build the itinerary together',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        if (latestUpdate != null && updateName != null) ...[
                          const SizedBox(height: 6),
                          Text(
                            '${latestUpdate.text} ┬╖ ${_timeAgo(latestUpdate.createdAt)} ┬╖ $updateName',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ],
                      ],
                    ),
                    Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            '$progress% done',
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                        if (canJumpToToday) ...[
                          const SizedBox(height: 6),
                          TextButton.icon(
                            onPressed: () => onSelectDay(todayIndex),
                            icon: const Icon(Icons.today_outlined, size: 16),
                            label: const Text('Today'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: _PlannerDayHeaderDelegate(
                child: _PlannerDaySelector(
                  days: days,
                  selectedDayIndex: selectedDayIndex,
                  onSelectDay: onSelectDay,
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: const SizedBox(height: 16),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  'Plans for $dayLabel',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            if (updates.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: _RecentUpdatesCard(
                    updates: updates.take(3).toList(),
                    members: trip.members,
                    profiles: profiles,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: const SizedBox(height: 12),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                child: Column(
                  children: ItinerarySection.values.map((section) {
                    return _PlannerSectionBlock(
                      section: section,
                      items: sectioned[section] ?? const [],
                      members: trip.members,
                      profiles: profiles,
                      categories: categories,
                      canEdit: canEdit,
                      onRequestUpgrade: onRequestUpgrade,
                      onAddItem: () => onAddItem(section),
                      onEditItem: onEditItem,
                      onEditNotes: onEditNotes,
                      onDeleteItem: onDeleteItem,
                      onToggleStatus: onToggleStatus,
                      onOpenComments: onOpenComments,
                      onReorderDay: onReorderDay,
                    );
                  }).toList(),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: canEdit
                ? () => onAddItem(_defaultSectionForNow())
                : onRequestUpgrade,
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }
}

class _PlannerDaySelector extends StatelessWidget {
  final List<DateTime> days;
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;

  const _PlannerDaySelector({
    required this.days,
    required this.selectedDayIndex,
    required this.onSelectDay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: days.length,
          separatorBuilder: (context, index) => const SizedBox(width: 8),
          itemBuilder: (context, index) {
            final date = days[index];
            final label =
                'Day ${index + 1} ┬╖ ${DateFormat('EEE, MMM d').format(date)}';
            final isActive = index == selectedDayIndex;
            return InkWell(
              onTap: () => onSelectDay(index),
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isActive ? const Color(0xFF0F172A) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isActive ? Colors.white : const Color(0xFF475569),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PlannerItineraryList extends StatelessWidget {
  final List<ItineraryItem> items;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final List<ItineraryCategory> categories;
  final bool canEdit;
  final VoidCallback onRequestUpgrade;
  final ValueChanged<ItineraryItem> onEditItem;
  final ValueChanged<ItineraryItem> onEditNotes;
  final ValueChanged<ItineraryItem> onDeleteItem;
  final ValueChanged<ItineraryItem> onToggleStatus;
  final ValueChanged<ItineraryItem> onOpenComments;
  final ValueChanged<List<ItineraryItem>> onReorderDay;

  const _PlannerItineraryList({
    required this.items,
    required this.members,
    required this.profiles,
    required this.categories,
    required this.canEdit,
    required this.onRequestUpgrade,
    required this.onEditItem,
    required this.onEditNotes,
    required this.onDeleteItem,
    required this.onToggleStatus,
    required this.onOpenComments,
    required this.onReorderDay,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: items.length,
      onReorder: (oldIndex, newIndex) {
        if (!canEdit) {
          onRequestUpgrade();
          return;
        }
        if (newIndex > oldIndex) newIndex -= 1;
        final reordered = [...items];
        final moved = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, moved);
        final updated = <ItineraryItem>[];
        for (var i = 0; i < reordered.length; i++) {
          updated.add(
            reordered[i].copyWith(order: i, updatedAt: DateTime.now()),
          );
        }
        onReorderDay(updated);
      },
      itemBuilder: (context, index) {
        final item = items[index];
        return _PlannerItemCard(
          key: ValueKey(item.id),
          item: item,
          members: members,
          profiles: profiles,
          categories: categories,
          canEdit: canEdit,
          onRequestUpgrade: onRequestUpgrade,
          dragHandle: canEdit
              ? ReorderableDragStartListener(
                  index: index,
                  child: const Icon(
                    Icons.drag_handle,
                    size: 18,
                    color: Color(0xFF94A3B8),
                  ),
                )
              : null,
          onEdit: () => onEditItem(item),
          onDelete: () => onDeleteItem(item),
          onToggleStatus: () => onToggleStatus(item),
          onEditNotes: () => onEditNotes(item),
          onOpenComments: () => onOpenComments(item),
        );
      },
    );
  }
}

class _PlannerSectionBlock extends StatelessWidget {
  final ItinerarySection section;
  final List<ItineraryItem> items;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final List<ItineraryCategory> categories;
  final bool canEdit;
  final VoidCallback onRequestUpgrade;
  final VoidCallback onAddItem;
  final ValueChanged<ItineraryItem> onEditItem;
  final ValueChanged<ItineraryItem> onEditNotes;
  final ValueChanged<ItineraryItem> onDeleteItem;
  final ValueChanged<ItineraryItem> onToggleStatus;
  final ValueChanged<ItineraryItem> onOpenComments;
  final ValueChanged<List<ItineraryItem>> onReorderDay;

  const _PlannerSectionBlock({
    required this.section,
    required this.items,
    required this.members,
    required this.profiles,
    required this.categories,
    required this.canEdit,
    required this.onRequestUpgrade,
    required this.onAddItem,
    required this.onEditItem,
    required this.onEditNotes,
    required this.onDeleteItem,
    required this.onToggleStatus,
    required this.onOpenComments,
    required this.onReorderDay,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _labelForSection(section),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: canEdit ? onAddItem : onRequestUpgrade,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add'),
              ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No plans yet.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                ),
              ),
            )
          else
            _PlannerItineraryList(
              items: items,
              members: members,
              profiles: profiles,
              categories: categories,
              canEdit: canEdit,
              onRequestUpgrade: onRequestUpgrade,
              onEditItem: onEditItem,
              onEditNotes: onEditNotes,
              onDeleteItem: onDeleteItem,
              onToggleStatus: onToggleStatus,
              onOpenComments: onOpenComments,
              onReorderDay: onReorderDay,
            ),
        ],
      ),
    );
  }
}

class _RecentUpdatesCard extends StatelessWidget {
  final List<TripUpdate> updates;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;

  const _RecentUpdatesCard({
    required this.updates,
    required this.members,
    required this.profiles,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent changes',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 8),
          ...updates.map((update) {
            final member = members.firstWhere(
              (m) => m.userId == update.actorId,
              orElse: () => members.first,
            );
            final name = _displayNameForUser(
              userId: member.userId,
              fallback: member.name,
              profiles: profiles,
            );
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${update.text} ┬╖ $name ┬╖ ${_timeAgo(update.createdAt)}',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _PlannerDayHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;

  const _PlannerDayHeaderDelegate({required this.child});

  @override
  double get minExtent => 68;

  @override
  double get maxExtent => 68;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return child;
  }

  @override
  bool shouldRebuild(covariant _PlannerDayHeaderDelegate oldDelegate) {
    return oldDelegate.child != child;
  }
}

class _PlannerItemCard extends StatefulWidget {
  final ItineraryItem item;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final List<ItineraryCategory> categories;
  final bool canEdit;
  final VoidCallback onRequestUpgrade;
  final VoidCallback onToggleStatus;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onEditNotes;
  final VoidCallback onOpenComments;
  final Widget? dragHandle;

  const _PlannerItemCard({
    super.key,
    required this.item,
    required this.members,
    required this.profiles,
    required this.categories,
    required this.canEdit,
    required this.onRequestUpgrade,
    required this.onToggleStatus,
    required this.onEdit,
    required this.onDelete,
    required this.onEditNotes,
    required this.onOpenComments,
    this.dragHandle,
  });

  @override
  State<_PlannerItemCard> createState() => _PlannerItemCardState();
}

class _PlannerItemCardState extends State<_PlannerItemCard> {
  bool _showNotes = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final assigneeId = item.assigneeId ?? item.assignedTo;
    final assigned = assigneeId == null
        ? null
        : widget.members.firstWhere(
            (m) => m.userId == assigneeId,
            orElse: () => widget.members.first,
          );
    final assigneeName = item.assigneeName ?? assigned?.name ?? 'Unassigned';
    final category = _categoryForItem(item, widget.categories);
    final categoryIcon = _iconForCategory(category);
    final timeLabel = item.isTimeSet
      ? DateFormat('h:mm a').format(item.dateTime)
      : 'Anytime';
    final statusLabel = _labelForStatus(item.status);
    final notesText = (item.notes ?? item.description ?? '').trim();
    final hasNotes = notesText.isNotEmpty;
    final linkText = (item.link ?? '').trim();
    final hasLink = linkText.isNotEmpty;
    final locationText = (item.location ?? '').trim();
    final hasLocation = locationText.isNotEmpty;
    final costLabel = item.cost == null
      ? null
      : NumberFormat.simpleCurrency().format(item.cost);
    final tags = item.tags;
    final updatedByMember = item.updatedBy == null
      ? null
      : widget.members.firstWhere(
        (m) => m.userId == item.updatedBy,
        orElse: () => widget.members.first,
        );
    final updatedByName = updatedByMember == null
      ? null
      : _displayNameForUser(
        userId: updatedByMember.userId,
        fallback: updatedByMember.name,
        profiles: widget.profiles,
        );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: item.status == ItineraryStatus.done
            ? const Color(0xFFECFDF3)
            : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: item.status == ItineraryStatus.done
              ? const Color(0xFFA7F3D0)
              : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Pill(
                icon: Icons.schedule,
                label: timeLabel,
              ),
              const SizedBox(width: 8),
              _Pill(
                icon: categoryIcon,
                label: category.label,
                background: const Color(0xFFFDF4FF),
                foreground: const Color(0xFF86198F),
              ),
              const Spacer(),
              _Pill(
                icon: null,
                label: statusLabel,
                background: item.status == ItineraryStatus.done
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF1F5F9),
                foreground: item.status == ItineraryStatus.done
                    ? const Color(0xFF15803D)
                    : const Color(0xFF64748B),
              ),
              const SizedBox(width: 6),
              if (widget.dragHandle != null) widget.dragHandle!,
              IconButton(
                tooltip: 'Edit item',
                icon: const Icon(Icons.edit_outlined, size: 18),
                color: const Color(0xFF475569),
                onPressed:
                    widget.canEdit ? widget.onEdit : widget.onRequestUpgrade,
              ),
              IconButton(
                tooltip: 'Delete item',
                icon: const Icon(Icons.delete_outline, size: 18),
                color: const Color(0xFF475569),
                onPressed:
                    widget.canEdit ? widget.onDelete : widget.onRequestUpgrade,
              ),
              IconButton(
                tooltip: 'Mark complete',
                icon: Icon(
                  item.status == ItineraryStatus.done
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                onPressed: widget.canEdit
                    ? widget.onToggleStatus
                    : widget.onRequestUpgrade,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          if (hasLocation) ...[
            const SizedBox(height: 6),
            Text(
              locationText,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Pill(
                icon: Icons.person_outline,
                label: assigneeName,
                background: const Color(0xFFF8FAFC),
                foreground: const Color(0xFF475569),
              ),
              if (costLabel != null)
                _Pill(
                  icon: Icons.payments_outlined,
                  label: costLabel,
                  background: const Color(0xFFF1F5F9),
                  foreground: const Color(0xFF475569),
                ),
              if (hasLocation)
                GestureDetector(
                  onTap: () => _openInMaps(context, locationText),
                  child: _Pill(
                    icon: Icons.map_outlined,
                    label: 'Maps',
                    background: const Color(0xFFF8FAFC),
                    foreground: const Color(0xFF475569),
                  ),
                ),
              if (hasLink)
                GestureDetector(
                  onTap: () => _openExternalLink(context, linkText),
                  onLongPress: () async {
                    await Clipboard.setData(ClipboardData(text: linkText));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Link copied')),
                    );
                  },
                  child: _Pill(
                    icon: Icons.link,
                    label: 'Link',
                    background: const Color(0xFFF8FAFC),
                    foreground: const Color(0xFF475569),
                  ),
                ),
              TextButton.icon(
                onPressed:
                    widget.canEdit ? widget.onEditNotes : widget.onRequestUpgrade,
                icon: Icon(hasNotes ? Icons.edit_note : Icons.add_comment),
                label: Text(hasNotes ? 'Edit note' : 'Add note'),
              ),
              TextButton.icon(
                onPressed: widget.onOpenComments,
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Comments'),
              ),
            ],
          ),
          if (hasNotes) ...[
            const SizedBox(height: 8),
            InkWell(
              onTap: () => setState(() => _showNotes = !_showNotes),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _showNotes ? 'Notes' : 'Notes (tap to expand)',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                        const Spacer(),
                        Icon(
                          _showNotes
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 18,
                          color: const Color(0xFF64748B),
                        ),
                      ],
                    ),
                    if (_showNotes) ...[
                      const SizedBox(height: 6),
                      Text(
                        notesText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              if (assigned != null) _Avatar(initials: _initials(assigned.name)),
              if (assigned != null) ...[
                const SizedBox(width: 8),
                Text(
                  'Assigned to ${assigned.name}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ],
          ),
          if (updatedByName != null) ...[
            const SizedBox(height: 6),
            Text(
              'Edited by $updatedByName ┬╖ ${_timeAgo(item.updatedAt)}',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: tags
                  .map(
                    (tag) => _Pill(
                      icon: Icons.sell_outlined,
                      label: tag,
                      background: const Color(0xFFF8FAFC),
                      foreground: const Color(0xFF64748B),
                    ),
                  )
                  .toList(),
            ),
          ],
          if (item.photoUrls.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: item.photoUrls.length,
                separatorBuilder: (_, index) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final url = item.photoUrls[index];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: url,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                        placeholder: (context, _) =>
                          Container(color: const Color(0xFFE2E8F0)),
                        errorWidget: (context, _, error) =>
                          Container(color: const Color(0xFFE2E8F0)),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ChecklistTab extends StatefulWidget {
  final Trip trip;
  final Map<String, UserProfile?> profiles;
  final String currentUserId;
  final bool canEditShared;
  final VoidCallback onRequestUpgrade;
  final Future<bool> Function(Trip, ChecklistItem) onUpsertShared;
  final Future<bool> Function(Trip, String) onDeleteShared;
  final Future<bool> Function(Trip, String, ChecklistItem) onUpsertPersonal;
  final Future<bool> Function(Trip, String, String) onDeletePersonal;
  final Future<bool> Function(Trip, String, bool) onSetPersonalVisibility;

  const _ChecklistTab({
    required this.trip,
    required this.profiles,
    required this.currentUserId,
    required this.canEditShared,
    required this.onRequestUpgrade,
    required this.onUpsertShared,
    required this.onDeleteShared,
    required this.onUpsertPersonal,
    required this.onDeletePersonal,
    required this.onSetPersonalVisibility,
  });

  @override
  State<_ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends State<_ChecklistTab> {
  final TextEditingController _quickAddController = TextEditingController();
  final TextEditingController _bulkAddController = TextEditingController();
  int _segmentIndex = 0;
  final Map<String, ChecklistItem> _sharedOverrides = {};
  final Map<String, ChecklistItem> _personalOverrides = {};
  bool? _personalVisibilityOverride;

  @override
  void dispose() {
    _quickAddController.dispose();
    _bulkAddController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final isMine = _segmentIndex == 0;
    final sharedItems = _sortedItems(
      _mergeItems(trip.checklist.sharedItems, _sharedOverrides),
    );
    final personalBase =
        trip.checklist.personalItemsByUserId[widget.currentUserId] ?? const [];
    final personalItems =
        _sortedItems(_mergeItems(personalBase, _personalOverrides));
    final personalVisibility = _personalVisibilityOverride ??
        trip.checklist.personalVisibilityByUserId[widget.currentUserId] ??
        false;
    final readiness = _readinessForTrip(
      trip,
      sharedItems: sharedItems,
      personalItemsForCurrentUser: personalItems,
    );
    final sharedLeft = readiness.sharedRemaining;
    final personalLeft = readiness.personalRemaining;
    final sharedProgress = readiness.sharedProgress;
    final personalProgress = readiness.personalProgress;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _ChecklistSummaryCard(
          readinessPercent: readiness.readinessPercent,
          sharedProgress: sharedProgress,
          personalProgress: personalProgress,
          remainingLabel:
              '$sharedLeft shared left ┬╖ $personalLeft personal left',
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _ChecklistSegmentedControl(
                index: _segmentIndex,
                onChanged: (value) => setState(() => _segmentIndex = value),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (isMine) ...[
          Text(
            'My checklist',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 12),
          _ChecklistVisibilityToggle(
            isShared: personalVisibility,
            onChanged: (value) => _updatePersonalVisibility(trip, value),
          ),
          const SizedBox(height: 12),
          _ChecklistQuickAddRow(
            controller: _quickAddController,
            onAdd: () => _handleQuickAdd(trip, isShared: false),
            onBulkAdd: () => _promptBulkAdd(trip, isShared: false),
          ),
          const SizedBox(height: 12),
          if (personalItems.isEmpty)
            _ChecklistEmptyState(
              title: 'No personal items yet',
              subtitle: 'Add your own packing list or start from a template.',
              icon: Icons.person_outline,
              onTemplate: () => _promptTemplate(trip),
            )
          else
            ..._buildSectionedItems(
              context,
              items: personalItems,
              trip: trip,
              ownerUserId: widget.currentUserId,
              canEdit: true,
              isSharedList: false,
            ),
        ] else ...[
          Text(
            'Shared logistics',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _ChecklistQuickAddRow(
            controller: _quickAddController,
            onAdd: () => _handleQuickAdd(trip, isShared: true),
            onBulkAdd: () => _promptBulkAdd(trip, isShared: true),
            canAdd: widget.canEditShared,
            onBlocked: widget.onRequestUpgrade,
          ),
          const SizedBox(height: 12),
          if (sharedItems.isEmpty)
            _ChecklistEmptyState(
              title: 'No shared tasks yet',
              subtitle: 'Add group items or start from a template.',
              icon: Icons.checklist_outlined,
              onTemplate: () => _promptTemplate(trip),
            )
          else
            ..._buildSectionedItems(
              context,
              items: sharedItems,
              trip: trip,
              ownerUserId: widget.currentUserId,
              canEdit: widget.canEditShared,
              isSharedList: true,
            ),
          const SizedBox(height: 16),
          ..._buildSharedPersonalLists(context, trip),
        ],
      ],
    );
  }

  List<ChecklistItem> _mergeItems(
    List<ChecklistItem> base,
    Map<String, ChecklistItem> overrides,
  ) {
    final merged = [...base];
    final byId = {for (final item in merged) item.id: item};
    for (final entry in overrides.entries) {
      if (!byId.containsKey(entry.key)) {
        merged.add(entry.value);
      }
    }
    for (var i = 0; i < merged.length; i++) {
      final override = overrides[merged[i].id];
      if (override != null) {
        merged[i] = override;
      }
    }
    return merged;
  }

  List<ChecklistItem> _sortedItems(List<ChecklistItem> items) {
    final sorted = [...items];
    sorted.sort((a, b) {
      if (a.isDone != b.isDone) {
        return a.isDone ? 1 : -1;
      }
      if (a.dueDate != null && b.dueDate != null) {
        final compare = a.dueDate!.compareTo(b.dueDate!);
        if (compare != 0) return compare;
      } else if (a.dueDate != null) {
        return -1;
      } else if (b.dueDate != null) {
        return 1;
      }
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return sorted;
  }

  Future<void> _handleQuickAdd(Trip trip, {required bool isShared}) async {
    if (isShared && !widget.canEditShared) {
      widget.onRequestUpgrade();
      return;
    }
    final text = _quickAddController.text.trim();
    if (text.isEmpty) return;
    _quickAddController.clear();
    final titles = _parseChecklistInput(text);
    await _addItems(trip, titles: titles, isShared: isShared);
  }

  Future<void> _promptBulkAdd(Trip trip, {required bool isShared}) async {
    if (isShared && !widget.canEditShared) {
      widget.onRequestUpgrade();
      return;
    }
    _bulkAddController.clear();
    final titles = await showDialog<List<String>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bulk add items'),
        content: TextField(
          controller: _bulkAddController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Add items separated by commas or new lines',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(
              _parseChecklistInput(_bulkAddController.text),
            ),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (titles == null || titles.isEmpty) return;
    await _addItems(trip, titles: titles, isShared: isShared);
  }

  List<String> _parseChecklistInput(String input) {
    return input
        .split(RegExp('[,\n]'))
        .map((entry) => entry.trim())
        .where((entry) => entry.isNotEmpty)
        .toList();
  }

  Future<void> _addItems(
    Trip trip, {
    required List<String> titles,
    required bool isShared,
    String? section,
  }) async {
    final now = DateTime.now();
    for (final title in titles) {
      final item = ChecklistItem(
        id: const Uuid().v4(),
        title: title,
        isDone: false,
        isShared: isShared,
        assignedUserId: isShared ? null : widget.currentUserId,
        section: section,
        createdAt: now,
        updatedAt: now,
      );
      if (isShared) {
        setState(() => _sharedOverrides[item.id] = item);
        final success = await widget.onUpsertShared(trip, item);
        if (!mounted) return;
        setState(() => _sharedOverrides.remove(item.id));
        if (!success) return;
      } else {
        setState(() => _personalOverrides[item.id] = item);
        final success = await widget.onUpsertPersonal(
          trip,
          widget.currentUserId,
          item,
        );
        if (!mounted) return;
        setState(() => _personalOverrides.remove(item.id));
        if (!success) return;
      }
    }
  }

  Future<void> _toggleItem(
    Trip trip, {
    required ChecklistItem item,
    required bool isShared,
    required String ownerUserId,
  }) async {
    final updated = item.copyWith(
      isDone: !item.isDone,
      isShared: isShared,
      updatedAt: DateTime.now(),
    );
    if (isShared) {
      final previous = _sharedOverrides[item.id] ?? item;
      setState(() => _sharedOverrides[item.id] = updated);
      final success = await widget.onUpsertShared(trip, updated);
      if (!mounted) return;
      if (success) {
        setState(() => _sharedOverrides.remove(item.id));
      } else {
        setState(() => _sharedOverrides[item.id] = previous);
      }
    } else {
      final previous = _personalOverrides[item.id] ?? item;
      setState(() => _personalOverrides[item.id] = updated);
      final success = await widget.onUpsertPersonal(trip, ownerUserId, updated);
      if (!mounted) return;
      if (success) {
        setState(() => _personalOverrides.remove(item.id));
      } else {
        setState(() => _personalOverrides[item.id] = previous);
      }
    }
  }

  Future<void> _deleteItem(
    Trip trip, {
    required ChecklistItem item,
    required bool isShared,
    required String ownerUserId,
  }) async {
    if (isShared) {
      await widget.onDeleteShared(trip, item.id);
    } else {
      await widget.onDeletePersonal(trip, ownerUserId, item.id);
    }
  }

  Future<void> _updatePersonalVisibility(Trip trip, bool value) async {
    setState(() => _personalVisibilityOverride = value);
    final success = await widget.onSetPersonalVisibility(
      trip,
      widget.currentUserId,
      value,
    );
    if (!mounted) return;
    if (!success) {
      setState(() => _personalVisibilityOverride = !value);
    } else {
      setState(() => _personalVisibilityOverride = null);
    }
  }

  Future<void> _promptTemplate(Trip trip) async {
    if (!widget.canEditShared) {
      widget.onRequestUpgrade();
      return;
    }
    final template = await showModalBottomSheet<ChecklistTemplate>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _ChecklistTemplateSheet(),
    );
    if (template == null) return;
    await _applyTemplate(trip, template);
  }

  Future<void> _applyTemplate(Trip trip, ChecklistTemplate template) async {
    final now = DateTime.now();
    for (final section in template.sections) {
      for (final entry in section.items) {
        final item = ChecklistItem(
          id: const Uuid().v4(),
          title: entry.title,
          isDone: false,
          isShared: entry.isShared,
          isCritical: entry.isCritical,
          assignedUserId:
              entry.isShared ? null : widget.currentUserId,
          section: section.title,
          createdAt: now,
          updatedAt: now,
        );
        if (entry.isShared) {
          setState(() => _sharedOverrides[item.id] = item);
          final success = await widget.onUpsertShared(trip, item);
          if (!mounted) return;
          setState(() => _sharedOverrides.remove(item.id));
          if (!success) return;
        } else {
          setState(() => _personalOverrides[item.id] = item);
          final success = await widget.onUpsertPersonal(
            trip,
            widget.currentUserId,
            item,
          );
          if (!mounted) return;
          setState(() => _personalOverrides.remove(item.id));
          if (!success) return;
        }
      }
    }
  }

  List<Widget> _buildSectionedItems(
    BuildContext context, {
    required List<ChecklistItem> items,
    required Trip trip,
    required String ownerUserId,
    required bool canEdit,
    required bool isSharedList,
    VoidCallback? onBlocked,
  }) {
    final groups = _groupBySection(items);
    final widgets = <Widget>[];
    for (final group in groups) {
      if (group.section != null && group.section!.isNotEmpty) {
        widgets.add(_ChecklistSectionHeader(title: group.section!));
      }
      for (final item in group.items) {
        widgets.add(
          _ChecklistItemTile(
            item: item,
            members: trip.members,
            profiles: widget.profiles,
            canEdit: canEdit,
            onBlocked: onBlocked ?? widget.onRequestUpgrade,
            onToggle: () => _toggleItem(
              trip,
              item: item,
              isShared: isSharedList,
              ownerUserId: ownerUserId,
            ),
            onDelete: () => _deleteItem(
              trip,
              item: item,
              isShared: isSharedList,
              ownerUserId: ownerUserId,
            ),
            onOpen: () => _openChecklistDetails(
              trip,
              item: item,
              isSharedList: isSharedList,
              ownerUserId: ownerUserId,
              canEdit: canEdit,
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<_ChecklistSectionGroup> _groupBySection(List<ChecklistItem> items) {
    final groups = <String?, List<ChecklistItem>>{};
    for (final item in items) {
      final key = (item.section ?? '').trim().isEmpty ? null : item.section;
      groups.putIfAbsent(key, () => []).add(item);
    }
    return groups.entries
        .map((entry) => _ChecklistSectionGroup(entry.key, entry.value))
        .toList();
  }

  List<Widget> _buildSharedPersonalLists(BuildContext context, Trip trip) {
    final widgets = <Widget>[];
    final visibility = trip.checklist.personalVisibilityByUserId;
    final sharedUsers = trip.members
        .where(
          (member) =>
              member.userId != widget.currentUserId &&
              visibility[member.userId] == true,
        )
        .toList();
    if (sharedUsers.isEmpty) return widgets;
    widgets.add(
      Text(
        'Shared personal lists',
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
    widgets.add(const SizedBox(height: 8));
    for (final member in sharedUsers) {
      final items =
          trip.checklist.personalItemsByUserId[member.userId] ?? const [];
      if (items.isEmpty) continue;
      final progress = _progressFor(items);
      widgets.add(
        _SharedPersonalChecklistCard(
          member: member,
          profiles: widget.profiles,
          progress: progress,
        ),
      );
      widgets.addAll(
        _buildSectionedItems(
          context,
          items: _sortedItems(items),
          trip: trip,
          ownerUserId: member.userId,
          canEdit: false,
          isSharedList: false,
          onBlocked: () {},
        ),
      );
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  Future<void> _openChecklistDetails(
    Trip trip, {
    required ChecklistItem item,
    required bool isSharedList,
    required String ownerUserId,
    required bool canEdit,
  }) async {
    final titleController = TextEditingController(text: item.title);
    final notesController = TextEditingController(text: item.notes ?? '');
    final linkController = TextEditingController(text: item.link ?? '');
    var dueDate = item.dueDate;
    final memberIds = trip.members.map((member) => member.userId).toSet();
    var assignedUserId =
      memberIds.contains(item.assignedUserId) ? item.assignedUserId : null;
    var isCritical = item.isCritical;
    final result = await showModalBottomSheet<_ChecklistDetailResult>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        final bottomInset = MediaQuery.of(context).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, bottomInset + 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Item details',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Title'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notesController,
                  enabled: canEdit,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Notes'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linkController,
                  enabled: canEdit,
                  decoration: const InputDecoration(labelText: 'Link'),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        dueDate == null
                            ? 'No due date'
                            : 'Due ${DateFormat('MMM d').format(dueDate!)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: !canEdit
                          ? null
                          : () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: dueDate ?? DateTime.now(),
                                firstDate: DateTime.now().subtract(
                                  const Duration(days: 365),
                                ),
                                lastDate: DateTime.now().add(
                                  const Duration(days: 365 * 3),
                                ),
                              );
                              if (picked == null) return;
                              setSheetState(() => dueDate = picked);
                            },
                      child: const Text('Pick date'),
                    ),
                    if (dueDate != null)
                      TextButton(
                        onPressed: !canEdit
                            ? null
                            : () => setSheetState(() => dueDate = null),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String?>(
                  initialValue: assignedUserId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Unassigned'),
                    ),
                    ...trip.members.map(
                      (member) => DropdownMenuItem<String?>(
                        value: member.userId,
                        child: Text(
                          _displayNameForUser(
                            userId: member.userId,
                            fallback: member.name,
                            profiles: widget.profiles,
                          ),
                        ),
                      ),
                    ),
                  ],
                  onChanged: !canEdit
                      ? null
                      : (value) => setSheetState(
                            () => assignedUserId = value,
                          ),
                  decoration: const InputDecoration(labelText: 'Assigned to'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: isCritical,
                  onChanged: canEdit
                      ? (value) => setSheetState(() => isCritical = value)
                      : null,
                  title: const Text('Critical item'),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(
                          _ChecklistDetailResult.delete(),
                        ),
                        child: const Text('Delete'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: !canEdit
                            ? null
                            : () => Navigator.of(context).pop(
                                  _ChecklistDetailResult.save(
                                    title: titleController.text.trim(),
                                    notes: notesController.text.trim(),
                                    link: linkController.text.trim(),
                                    dueDate: dueDate,
                                    assignedUserId: assignedUserId,
                                    isCritical: isCritical,
                                  ),
                                ),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (result == null) return;
    if (result.isDelete) {
      await _deleteItem(
        trip,
        item: item,
        isShared: isSharedList,
        ownerUserId: ownerUserId,
      );
      return;
    }
    if (!result.isSave) return;
    final updated = item.copyWith(
      title: result.title.isEmpty ? item.title : result.title,
      notes: result.notes.isEmpty ? null : result.notes,
      link: result.link.isEmpty ? null : result.link,
      dueDate: result.dueDate,
      assignedUserId: result.assignedUserId,
      isCritical: result.isCritical,
      isShared: isSharedList,
      updatedAt: DateTime.now(),
    );
    if (isSharedList) {
      setState(() => _sharedOverrides[item.id] = updated);
      final success = await widget.onUpsertShared(trip, updated);
      if (!mounted) return;
      if (success) {
        setState(() => _sharedOverrides.remove(item.id));
      }
    } else {
      setState(() => _personalOverrides[item.id] = updated);
      final success = await widget.onUpsertPersonal(
        trip,
        ownerUserId,
        updated,
      );
      if (!mounted) return;
      if (success) {
        setState(() => _personalOverrides.remove(item.id));
      }
    }
  }

  _ChecklistReadiness _readinessForTrip(
    Trip trip, {
    required List<ChecklistItem> sharedItems,
    required List<ChecklistItem> personalItemsForCurrentUser,
  }) {
    final sharedProgress = _progressFor(sharedItems);
    final personalByUser = Map<String, List<ChecklistItem>>.from(
      trip.checklist.personalItemsByUserId,
    )
      ..[widget.currentUserId] = personalItemsForCurrentUser;
    final personalTotals = personalByUser.values.fold<
        _ChecklistProgress>(
      const _ChecklistProgress(done: 0, total: 0),
      (current, list) {
        final progress = _progressFor(list);
        return _ChecklistProgress(
          done: current.done + progress.done,
          total: current.total + progress.total,
        );
      },
    );
    final personalProgress = personalTotals;
    final personalAverage = trip.members.isEmpty
        ? 0.0
        : trip.members
                .map((member) {
                  final list = personalByUser[member.userId] ?? const [];
                  final progress = _progressFor(list);
                  return progress.total == 0
                      ? 0.0
                      : progress.done / progress.total;
                })
                .reduce((a, b) => a + b) /
            trip.members.length;
    final sharedCompletion = sharedProgress.total == 0
        ? 0.0
        : sharedProgress.done / sharedProgress.total;
    final readiness =
        (0.7 * sharedCompletion) + (0.3 * personalAverage);
    final readinessPercent = (readiness * 100).round();
    return _ChecklistReadiness(
      readinessPercent: readinessPercent.clamp(0, 100).toInt(),
      sharedProgress: sharedProgress,
      personalProgress: personalProgress,
    );
  }

  _ChecklistProgress _progressFor(List<ChecklistItem> items) {
    final done = items.where((item) => item.isDone).length;
    return _ChecklistProgress(done: done, total: items.length);
  }
}

class _ChecklistSegmentedControl extends StatelessWidget {
  final int index;
  final ValueChanged<int> onChanged;

  const _ChecklistSegmentedControl({
    required this.index,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _SegmentOption(
            label: 'Mine',
            isActive: index == 0,
            onTap: () => onChanged(0),
          ),
          _SegmentOption(
            label: 'Shared',
            isActive: index == 1,
            onTap: () => onChanged(1),
          ),
        ],
      ),
    );
  }
}

class _SegmentOption extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SegmentOption({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: isActive ? const Color(0xFF0F172A) : const Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

class _ChecklistSummaryCard extends StatelessWidget {
  final int readinessPercent;
  final _ChecklistProgress sharedProgress;
  final _ChecklistProgress personalProgress;
  final String remainingLabel;

  const _ChecklistSummaryCard({
    required this.readinessPercent,
    required this.sharedProgress,
    required this.personalProgress,
    required this.remainingLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Trip readiness',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$readinessPercent%',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  remainingLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _ChecklistProgressRow(
            label: 'Shared',
            progress: sharedProgress,
          ),
          const SizedBox(height: 6),
          _ChecklistProgressRow(
            label: 'Personal',
            progress: personalProgress,
          ),
        ],
      ),
    );
  }
}

class _ChecklistProgressRow extends StatelessWidget {
  final String label;
  final _ChecklistProgress progress;

  const _ChecklistProgressRow({
    required this.label,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final percent = progress.total == 0
        ? 0
        : (progress.done / progress.total * 100).round();
    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: progress.total == 0 ? 0 : progress.done / progress.total,
              minHeight: 8,
              backgroundColor: const Color(0xFFF1F5F9),
              color: const Color(0xFF4F46E5),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$percent%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _ChecklistVisibilityToggle extends StatelessWidget {
  final bool isShared;
  final ValueChanged<bool> onChanged;

  const _ChecklistVisibilityToggle({
    required this.isShared,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isShared ? 'Shared with group' : 'Private to you',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  isShared
                      ? 'Everyone can view your personal list.'
                      : 'Only you can see your personal list.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: isShared,
            onChanged: onChanged,
            activeThumbColor: const Color(0xFF4F46E5),
            activeTrackColor: const Color(0xFFC7D2FE),
          ),
        ],
      ),
    );
  }
}

class _ChecklistQuickAddRow extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onAdd;
  final VoidCallback onBulkAdd;
  final bool canAdd;
  final VoidCallback? onBlocked;

  const _ChecklistQuickAddRow({
    required this.controller,
    required this.onAdd,
    required this.onBulkAdd,
    this.canAdd = true,
    this.onBlocked,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Add items (comma-separated works)',
            ),
            onSubmitted: (_) => canAdd ? onAdd() : onBlocked?.call(),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: canAdd ? onAdd : onBlocked,
          child: const Text('Add'),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: canAdd ? onBulkAdd : onBlocked,
          child: const Text('Bulk'),
        ),
      ],
    );
  }
}

class _ChecklistEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTemplate;

  const _ChecklistEmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTemplate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF94A3B8)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onTemplate,
            icon: const Icon(Icons.auto_awesome_outlined, size: 18),
            label: const Text('Start from template'),
          ),
        ],
      ),
    );
  }
}

class _ChecklistSectionHeader extends StatelessWidget {
  final String title;

  const _ChecklistSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 6),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: const Color(0xFF94A3B8),
        ),
      ),
    );
  }
}

class _ChecklistItemTile extends StatelessWidget {
  final ChecklistItem item;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final bool canEdit;
  final VoidCallback? onBlocked;
  final VoidCallback onToggle;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  const _ChecklistItemTile({
    required this.item,
    required this.members,
    required this.profiles,
    required this.canEdit,
    required this.onBlocked,
    required this.onToggle,
    required this.onDelete,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final assigned = item.assignedUserId == null
        ? null
        : members.firstWhere(
            (m) => m.userId == item.assignedUserId,
            orElse: () => members.first,
          );
    final assigneeName = item.assignedUserId == null
        ? null
        : _displayNameForUser(
            userId: item.assignedUserId!,
            fallback: assigned?.name ?? 'Assigned',
            profiles: profiles,
          );
    final dueLabel = item.dueDate == null
        ? null
        : DateFormat('MMM d').format(item.dueDate!);
    final hasNotes = (item.notes ?? '').trim().isNotEmpty;
    final hasLink = (item.link ?? '').trim().isNotEmpty;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: item.isDone,
                  onChanged:
                      canEdit ? (_) => onToggle() : (_) => onBlocked?.call(),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    item.title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      decoration:
                          item.isDone ? TextDecoration.lineThrough : null,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete item',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: canEdit ? onDelete : onBlocked,
                ),
              ],
            ),
            if (assigneeName != null || dueLabel != null || hasNotes || hasLink)
              Padding(
                padding: const EdgeInsets.only(left: 40, top: 6),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    if (assigneeName != null)
                      _ChecklistMetaPill(
                        icon: Icons.person_outline,
                        label: assigneeName,
                      ),
                    if (dueLabel != null)
                      _ChecklistMetaPill(
                        icon: Icons.event_outlined,
                        label: dueLabel,
                      ),
                    if (hasNotes)
                      const _ChecklistMetaPill(
                        icon: Icons.sticky_note_2_outlined,
                        label: 'Notes',
                      ),
                    if (hasLink)
                      const _ChecklistMetaPill(
                        icon: Icons.link,
                        label: 'Link',
                      ),
                    if (item.isCritical)
                      const _ChecklistMetaPill(
                        icon: Icons.warning_amber_outlined,
                        label: 'Critical',
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistMetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ChecklistMetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF64748B)),
          const SizedBox(width: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ],
      ),
    );
  }
}

class _SharedPersonalChecklistCard extends StatelessWidget {
  final Member member;
  final Map<String, UserProfile?> profiles;
  final _ChecklistProgress progress;

  const _SharedPersonalChecklistCard({
    required this.member,
    required this.profiles,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final displayName = _displayNameForUser(
      userId: member.userId,
      fallback: member.name,
      profiles: profiles,
    );
    final photoUrl = _photoUrlForUser(
      userId: member.userId,
      fallback: member.avatarUrl,
      profiles: profiles,
    );
    final percent = progress.total == 0
        ? 0
        : (progress.done / progress.total * 100).round();
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _Avatar(initials: _initials(displayName), photoUrl: photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$percent% complete',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
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

class _ChecklistSectionGroup {
  final String? section;
  final List<ChecklistItem> items;

  const _ChecklistSectionGroup(this.section, this.items);
}

class _ChecklistProgress {
  final int done;
  final int total;

  const _ChecklistProgress({required this.done, required this.total});
}

class _ChecklistReadiness {
  final int readinessPercent;
  final _ChecklistProgress sharedProgress;
  final _ChecklistProgress personalProgress;

  const _ChecklistReadiness({
    required this.readinessPercent,
    required this.sharedProgress,
    required this.personalProgress,
  });

  int get sharedRemaining => sharedProgress.total - sharedProgress.done;
  int get personalRemaining => personalProgress.total - personalProgress.done;
}

class _ChecklistDetailResult {
  final bool isSave;
  final bool isDelete;
  final String title;
  final String notes;
  final String link;
  final DateTime? dueDate;
  final String? assignedUserId;
  final bool isCritical;

  const _ChecklistDetailResult._({
    required this.isSave,
    required this.isDelete,
    this.title = '',
    this.notes = '',
    this.link = '',
    this.dueDate,
    this.assignedUserId,
    this.isCritical = false,
  });

  factory _ChecklistDetailResult.save({
    required String title,
    required String notes,
    required String link,
    required DateTime? dueDate,
    required String? assignedUserId,
    required bool isCritical,
  }) {
    return _ChecklistDetailResult._(
      isSave: true,
      isDelete: false,
      title: title,
      notes: notes,
      link: link,
      dueDate: dueDate,
      assignedUserId: assignedUserId,
      isCritical: isCritical,
    );
  }

  factory _ChecklistDetailResult.delete() {
    return const _ChecklistDetailResult._(isSave: false, isDelete: true);
  }
}

class _ChecklistTemplateSheet extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Start with a template',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: ListView.separated(
              itemCount: checklistTemplates.length,
              separatorBuilder: (_, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final template = checklistTemplates[index];
                return InkWell(
                  onTap: () => Navigator.of(context).pop(template),
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.title,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          template.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _StoryTab extends StatelessWidget {
  final Trip trip;
  final Map<String, UserProfile?> profiles;
  final List<WallComment> comments;
  final TextEditingController commentController;
  final VoidCallback onSendComment;
  final VoidCallback onRequestUpgrade;
  final bool canPost;
  final ValueChanged<bool> onTogglePublish;
  final ValueChanged<StoryMoment> onToggleMoment;
  final bool isSendingComment;
  final bool isPublishing;
  final int likeCount;

  const _StoryTab({
    required this.trip,
    required this.profiles,
    required this.comments,
    required this.commentController,
    required this.onSendComment,
    required this.onRequestUpgrade,
    required this.canPost,
    required this.onTogglePublish,
    required this.onToggleMoment,
    required this.isSendingComment,
    required this.isPublishing,
    required this.likeCount,
  });

  @override
  Widget build(BuildContext context) {
    final stats = trip.story.wallStats;
    final isPublished = trip.story.publishToWall;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Publish story',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Share your trip on the wall so friends can follow along.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            _StatusBadge(
              label: isPublished ? 'On Wall' : 'Off Wall',
              tone: isPublished
                  ? const Color(0xFFE0F2FE)
                  : const Color(0xFFF1F5F9),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: isPublishing
                    ? null
                    : canPost
                    ? () => onTogglePublish(true)
                    : onRequestUpgrade,
                child: Text(
                  isPublished ? 'Preview update' : 'Preview & publish',
                ),
              ),
            ),
            if (isPublished) ...[
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: isPublishing
                      ? null
                      : canPost
                      ? () => onTogglePublish(false)
                      : onRequestUpgrade,
                  child: const Text('Remove from wall'),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 140,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                  gradient: _gradientForTrip(trip),
                  image: trip.heroImageUrl != null
                      ? DecorationImage(
                          image: CachedNetworkImageProvider(trip.heroImageUrl!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      trip.story.headline.isNotEmpty
                          ? trip.story.headline
                          : '${trip.destination} passport',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      trip.story.highlights.isNotEmpty
                          ? trip.story.highlights.take(3).join(' ┬╖ ')
                          : 'Add highlights to make the story pop.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Icon(Icons.favorite_border, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('$likeCount',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(width: 16),
                        Icon(Icons.chat_bubble_outline,
                            size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text('${stats.comments}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Moments',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (trip.story.moments.isEmpty)
          const _InlineEmptyState(
            title: 'No moments yet',
            subtitle: 'Add quick notes and keep the story alive.',
            icon: Icons.auto_awesome_outlined,
          )
        else
          ...trip.story.moments.map(
            (moment) => _MomentCard(
              moment: moment,
              members: trip.members,
              profiles: profiles,
              onToggleVisibility: canPost
                  ? () => onToggleMoment(moment)
                  : null,
            ),
          ),
        const SizedBox(height: 16),
        Text(
          'Photos',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (trip.story.photos.isEmpty)
          const _InlineEmptyState(
            title: 'No photos yet',
            subtitle: 'Drop your first snapshot to start a visual recap.',
            icon: Icons.photo_outlined,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: trip.story.photos
                .take(6)
                .map((photo) => _PhotoTile(photo: photo))
                .toList(),
          ),
        const SizedBox(height: 16),
        Text(
          'Comments',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 8),
        if (comments.isEmpty)
          const _InlineEmptyState(
            title: 'No comments yet',
            subtitle: 'Be the first to react to this story.',
            icon: Icons.chat_bubble_outline,
          )
        else
          ...comments.map(
            (comment) => _CommentCard(
              comment: comment,
              members: trip.members,
              profiles: profiles,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: commentController,
                decoration: InputDecoration(
                  hintText: 'Write a comment...',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                enabled: canPost,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: isSendingComment
                  ? null
                  : canPost
                  ? onSendComment
                  : onRequestUpgrade,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }
}

class _PeopleTab extends StatelessWidget {
  final Trip trip;
  final Map<String, UserProfile?> profiles;
  final VoidCallback onRequestJoin;
  final void Function(String, JoinRequestStatus) onRespondJoin;
  final String currentUserId;
  final VoidCallback onAddFromFriends;
  final VoidCallback onInvite;
  final Future<void> Function(String, MemberRole) onUpdateRole;
  final Future<void> Function(String) onRemoveMember;
  final Future<void> Function() onLeaveTrip;
  final VoidCallback onRequestUpgrade;
  final ValueChanged<TripPrivacyOption> onUpdatePrivacy;
  final bool canInvite;
  final bool canManagePeople;
  final bool canChangePrivacy;
  final String? inviteLink;
  final bool isJoinRequestBusy;
  final bool Function(String requestId) isResponding;

  const _PeopleTab({
    required this.trip,
    required this.profiles,
    required this.onRequestJoin,
    required this.onRespondJoin,
    required this.currentUserId,
    required this.onAddFromFriends,
    required this.onInvite,
    required this.onUpdateRole,
    required this.onRemoveMember,
    required this.onLeaveTrip,
    required this.onRequestUpgrade,
    required this.onUpdatePrivacy,
    required this.canInvite,
    required this.canManagePeople,
    required this.canChangePrivacy,
    required this.inviteLink,
    required this.isJoinRequestBusy,
    required this.isResponding,
  });

  @override
  Widget build(BuildContext context) {
    final pending = trip.joinRequests
        .where((r) => r.status == JoinRequestStatus.pending)
        .toList();
    final isMember = trip.members.any((m) => m.userId == currentUserId);
    Member? currentMember;
    try {
      currentMember =
        trip.members.firstWhere((m) => m.userId == currentUserId);
    } catch (_) {}
    final roleLabel =
        currentMember == null ? 'Guest' : _roleLabel(currentMember.role);
    final privacyOption = _privacyOptionForTrip(trip);
    JoinRequest? myRequest;
    try {
      myRequest = trip.joinRequests.firstWhere(
        (r) => r.userId == currentUserId,
      );
    } catch (_) {}

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your role: $roleLabel',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _roleSummary(roleLabel),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Members',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: canInvite ? onAddFromFriends : onRequestUpgrade,
              icon: const Icon(Icons.group_add_outlined, size: 18),
              label: const Text('Add from Friends'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: canInvite ? onInvite : onRequestUpgrade,
              icon: const Icon(Icons.link_outlined, size: 18),
              label: const Text('Invite link'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...trip.members.map(
          (member) => _MemberTile(
            member: member,
            profiles: profiles,
            ownerId: trip.ownerId,
            currentUserId: currentUserId,
            canManagePeople: canManagePeople,
            onUpdateRole: onUpdateRole,
            onRemoveMember: onRemoveMember,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Role permissions',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        _RoleGuideCard(),
        const SizedBox(height: 16),
        Text(
          'Trip privacy',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TripPrivacyOption.values.map((option) {
                  return ChoiceChip(
                    label: Text(_privacyLabel(option)),
                    selected: privacyOption == option,
                    onSelected: (value) {
                      if (!value) return;
                      if (!canChangePrivacy) {
                        onRequestUpgrade();
                        return;
                      }
                      onUpdatePrivacy(option);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              Text(
                _privacyDescription(privacyOption),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                ),
              ),
              if (!canChangePrivacy) ...[
                const SizedBox(height: 8),
                Text(
                  'Only the owner can change privacy settings.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Invitations',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      inviteLink == null
                          ? 'No active invite link'
                          : 'Invite link ready to share',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Create a link, share it, or refresh it any time.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: canInvite ? onInvite : onRequestUpgrade,
                child: const Text('Manage'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Text(
              'Join requests',
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 8),
            if (pending.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  pending.length.toString(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const _InlineEmptyState(
            title: 'No pending requests',
            subtitle: 'Invite someone to start collaborating.',
            icon: Icons.mail_outline,
          )
        else
          ...pending.map(
            (request) => _JoinRequestCard(
              request: request,
              members: trip.members,
              profiles: profiles,
              onRespond: onRespondJoin,
              isBusy: isResponding(request.id),
              canRespond: canManagePeople,
              onRequestUpgrade: onRequestUpgrade,
            ),
          ),
        if (!isMember && trip.audience.allowJoinRequests && myRequest == null)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: ElevatedButton(
              onPressed: isJoinRequestBusy ? null : onRequestJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Request to join'),
            ),
          ),
        if (myRequest != null && !isMember)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: _InlineEmptyState(
              title: 'Request sent',
              subtitle: _joinStatusCopy(myRequest.status),
              icon: Icons.schedule_send,
            ),
          ),
        if (isMember) ...[
          const SizedBox(height: 16),
          Text(
            'Leave trip',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFECACA)),
            ),
            child: Row(
              children: [
                const Icon(Icons.exit_to_app, color: Color(0xFFB91C1C)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Leaving removes your access to this trip.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF991B1B),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFB91C1C),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: onLeaveTrip,
                  child: const Text('Leave'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ChatTab extends StatefulWidget {
  final Trip trip;
  final Map<String, UserProfile?> profiles;
  final List<ChatMessage> messages;
  final TextEditingController chatController;
  final VoidCallback onSend;
  final bool canPost;
  final VoidCallback onRequestUpgrade;
  final String currentUserId;
  final bool isSending;
  final List<_PendingChatEntry> pendingMessages;
  final bool canLoadMore;
  final bool isLoadingMore;
  final VoidCallback onLoadMore;
  final void Function(_PendingChatEntry entry) onRetry;

  const _ChatTab({
    required this.trip,
    required this.profiles,
    required this.messages,
    required this.chatController,
    required this.onSend,
    required this.canPost,
    required this.onRequestUpgrade,
    required this.currentUserId,
    required this.isSending,
    required this.pendingMessages,
    required this.canLoadMore,
    required this.isLoadingMore,
    required this.onLoadMore,
    required this.onRetry,
  });

  @override
  State<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends State<_ChatTab> {
  final Set<String> _expandedTimestamps = {};

  void _toggleTimestamp(String id) {
    setState(() {
      if (_expandedTimestamps.contains(id)) {
        _expandedTimestamps.remove(id);
      } else {
        _expandedTimestamps.add(id);
      }
    });
  }

  Future<void> _copyMessage(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Message copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pending = widget.pendingMessages;
    final messages = widget.messages;
    return Column(
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              if (messages.isEmpty && pending.isEmpty)
                const _InlineEmptyState(
                  title: 'No messages yet',
                  subtitle: 'Say hi and keep the trip aligned in real time.',
                  icon: Icons.chat_outlined,
                )
              else
                ...[
                  if (widget.canLoadMore)
                    TextButton.icon(
                      onPressed: widget.isLoadingMore
                          ? null
                          : widget.onLoadMore,
                      icon: widget.isLoadingMore
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.history, size: 16),
                      label: Text(
                        widget.isLoadingMore
                            ? 'Loading...'
                            : 'Load earlier messages',
                      ),
                    ),
                  ...messages.map(
                    (message) => _ChatBubble(
                      message: message,
                      members: widget.trip.members,
                      profiles: widget.profiles,
                      currentUserId: widget.currentUserId,
                      showTimestamp: _expandedTimestamps.contains(message.id),
                      onLongPress: () async {
                        _toggleTimestamp(message.id);
                        await _copyMessage(context, message.text);
                      },
                    ),
                  ),
                  ...pending.map(
                    (entry) => _ChatBubble(
                      message: entry.message,
                      members: widget.trip.members,
                      profiles: widget.profiles,
                      currentUserId: widget.currentUserId,
                      showTimestamp: false,
                      onLongPress: () {},
                      isPending: !entry.isFailed,
                      isFailed: entry.isFailed,
                      onRetry: entry.isFailed
                          ? () => widget.onRetry(entry)
                          : null,
                    ),
                  ),
                ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.chatController,
                  decoration: InputDecoration(
                    hintText: 'Message the trip...',
                    filled: true,
                    fillColor: const Color(0xFFF1F5F9),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(999),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  enabled: widget.canPost,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Send message',
                onPressed: widget.isSending
                    ? null
                    : widget.canPost
                    ? widget.onSend
                    : widget.onRequestUpgrade,
                icon: const Icon(Icons.send, color: Color(0xFF4F46E5)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MomentCard extends StatelessWidget {
  final StoryMoment moment;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final VoidCallback? onToggleVisibility;

  const _MomentCard({
    required this.moment,
    required this.members,
    required this.profiles,
    this.onToggleVisibility,
  });

  @override
  Widget build(BuildContext context) {
    final author = members.firstWhere(
      (m) => m.userId == moment.authorId,
      orElse: () => members.first,
    );
    final authorName = _displayNameForUser(
      userId: author.userId,
      fallback: author.name,
      profiles: profiles,
    );
    final authorPhoto = _photoUrlForUser(
      userId: author.userId,
      fallback: author.avatarUrl,
      profiles: profiles,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Avatar(initials: _initials(authorName), photoUrl: authorPhoto),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  moment.caption,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                if (!moment.isPublic) ...[
                  const SizedBox(height: 6),
                  _StatusBadge(
                    label: 'Hidden from wall',
                    tone: const Color(0xFFFEE2E2),
                  ),
                ],
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _timeAgo(moment.createdAt),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(
                  color: const Color(0xFF94A3B8),
                ),
              ),
              if (onToggleVisibility != null) ...[
                const SizedBox(height: 6),
                IconButton(
                  tooltip: moment.isPublic
                      ? 'Hide from wall'
                      : 'Show on wall',
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    moment.isPublic
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final WallComment comment;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;

  const _CommentCard({
    required this.comment,
    required this.members,
    required this.profiles,
  });

  @override
  Widget build(BuildContext context) {
    final author = members.firstWhere(
      (m) => m.userId == comment.authorId,
      orElse: () => members.first,
    );
    final authorName = _displayNameForUser(
      userId: author.userId,
      fallback: author.name,
      profiles: profiles,
    );
    final authorPhoto = _photoUrlForUser(
      userId: author.userId,
      fallback: author.avatarUrl,
      profiles: profiles,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _Avatar(initials: _initials(authorName), photoUrl: authorPhoto),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  comment.text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _timeAgo(comment.createdAt),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: const Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

class _ItineraryCommentsSheet extends ConsumerStatefulWidget {
  final String tripId;
  final ItineraryItem item;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final bool canPost;
  final VoidCallback onRequestUpgrade;

  const _ItineraryCommentsSheet({
    required this.tripId,
    required this.item,
    required this.members,
    required this.profiles,
    required this.canPost,
    required this.onRequestUpgrade,
  });

  @override
  ConsumerState<_ItineraryCommentsSheet> createState() =>
      _ItineraryCommentsSheetState();
}

class _ItineraryCommentsSheetState
    extends ConsumerState<_ItineraryCommentsSheet> {
  final TextEditingController _controller = TextEditingController();
  bool _isSending = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _sendComment() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;
    if (!widget.canPost) {
      widget.onRequestUpgrade();
      return;
    }
    setState(() => _isSending = true);
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to comment on this item.',
    );
    if (!mounted) return;
    if (!allowed) {
      setState(() => _isSending = false);
      return;
    }
    final session = ref.read(authSessionProvider).value;
    if (session == null) {
      setState(() => _isSending = false);
      return;
    }
    final comment = ItineraryComment(
      id: const Uuid().v4(),
      authorId: session.userId,
      text: text,
      createdAt: DateTime.now(),
    );
    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.addItineraryComment(
          widget.tripId,
          widget.item.id,
          comment,
        );
        _controller.clear();
      },
      errorMessage: 'Unable to send comment.',
    );
    if (!mounted) return;
    if (!success && _controller.text.isEmpty) {
      _controller.text = text;
    }
    setState(() => _isSending = false);
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = ref.watch(
      itineraryCommentsStreamProvider((widget.tripId, widget.item.id)),
    );
    final comments = commentsAsync.value ?? const <ItineraryComment>[];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Comments',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.item.title,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        if (comments.isEmpty)
          const _InlineEmptyState(
            title: 'No comments yet',
            subtitle: 'Add the first note for this item.',
            icon: Icons.chat_bubble_outline,
          )
        else
          ...comments.map(
            (comment) => _ItineraryCommentCard(
              comment: comment,
              members: widget.members,
              profiles: widget.profiles,
            ),
          ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                decoration: InputDecoration(
                  hintText: 'Write a comment... ',
                  filled: true,
                  fillColor: const Color(0xFFF8FAFC),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: BorderSide.none,
                  ),
                ),
                enabled: widget.canPost,
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSending
                  ? null
                  : widget.canPost
                  ? _sendComment
                  : widget.onRequestUpgrade,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Send'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ItineraryCommentCard extends StatelessWidget {
  final ItineraryComment comment;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;

  const _ItineraryCommentCard({
    required this.comment,
    required this.members,
    required this.profiles,
  });

  @override
  Widget build(BuildContext context) {
    final author = members.firstWhere(
      (m) => m.userId == comment.authorId,
      orElse: () => members.first,
    );
    final authorName = _displayNameForUser(
      userId: author.userId,
      fallback: author.name,
      profiles: profiles,
    );
    final authorPhoto = _photoUrlForUser(
      userId: author.userId,
      fallback: author.avatarUrl,
      profiles: profiles,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _Avatar(initials: _initials(authorName), photoUrl: authorPhoto),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  authorName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  comment.text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
              ],
            ),
          ),
          Text(
            _timeAgo(comment.createdAt),
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: const Color(0xFF94A3B8)),
          ),
        ],
      ),
    );
  }
}

class _PhotoTile extends StatelessWidget {
  final StoryPhoto photo;

  const _PhotoTile({required this.photo});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: CachedNetworkImage(
        imageUrl: photo.url,
        width: 100,
        height: 100,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            Container(color: const Color(0xFFE2E8F0)),
        errorWidget: (context, url, error) =>
            Container(color: const Color(0xFFE2E8F0)),
      ),
    );
  }
}

class _JoinRequestCard extends StatelessWidget {
  final JoinRequest request;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final void Function(String, JoinRequestStatus) onRespond;
  final bool isBusy;
  final bool canRespond;
  final VoidCallback onRequestUpgrade;

  const _JoinRequestCard({
    required this.request,
    required this.members,
    required this.profiles,
    required this.onRespond,
    required this.isBusy,
    required this.canRespond,
    required this.onRequestUpgrade,
  });

  @override
  Widget build(BuildContext context) {
    final author = members.firstWhere(
      (m) => m.userId == request.userId,
      orElse: () => members.first,
    );
    final authorName = _displayNameForUser(
      userId: request.userId,
      fallback: author.name,
      profiles: profiles,
    );
    final authorPhoto = _photoUrlForUser(
      userId: request.userId,
      fallback: author.avatarUrl,
      profiles: profiles,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: _initials(authorName), photoUrl: authorPhoto),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      authorName,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      request.note,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF475569),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: isBusy
                      ? null
                      : canRespond
                      ? () =>
                          onRespond(request.id, JoinRequestStatus.approved)
                      : onRequestUpgrade,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF22C55E),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Approve'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: isBusy
                      ? null
                      : canRespond
                      ? () =>
                          onRespond(request.id, JoinRequestStatus.declined)
                      : onRequestUpgrade,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Decline'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Member member;
  final Map<String, UserProfile?> profiles;
  final String ownerId;
  final String currentUserId;
  final bool canManagePeople;
  final Future<void> Function(String, MemberRole) onUpdateRole;
  final Future<void> Function(String) onRemoveMember;

  const _MemberTile({
    required this.member,
    required this.profiles,
    required this.ownerId,
    required this.currentUserId,
    required this.canManagePeople,
    required this.onUpdateRole,
    required this.onRemoveMember,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel(member.role);
    final displayName = _displayNameForUser(
      userId: member.userId,
      fallback: member.name,
      profiles: profiles,
    );
    final photoUrl = _photoUrlForUser(
      userId: member.userId,
      fallback: member.avatarUrl,
      profiles: profiles,
    );
    final joinedLabel = DateFormat('MMM d, yyyy').format(member.joinedAt);
    final invitedById = member.invitedBy;
    String? invitedByName;
    if (invitedById != null && invitedById.isNotEmpty) {
      final profile = profiles[invitedById];
      invitedByName =
          (profile?.displayName.isNotEmpty == true ? profile!.displayName : null)
              ?? (invitedById == ownerId ? 'Owner' : null);
    }
    final metaParts = <String>['Joined on $joinedLabel'];
    if (invitedByName != null) {
      metaParts.add('Invited by $invitedByName');
    }
    final metaLine = metaParts.join(' ┬╖ ');
    final isSelf = member.userId == currentUserId;
    final canShowActions = canManagePeople && !isSelf;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          _Avatar(initials: _initials(displayName), photoUrl: photoUrl),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  metaLine,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
          _StatusBadge(
            label: roleLabel,
            tone: const Color(0xFFF1F5F9),
          ),
          if (canShowActions)
            PopupMenuButton<_MemberAction>(
              icon: const Icon(Icons.more_vert, size: 20),
              onSelected: (action) async {
                final targetRole = _roleForAction(action);
                if (action == _MemberAction.remove) {
                  final confirmed = await _confirmMemberAction(
                    context,
                    title: 'Remove $displayName?',
                    body: 'They will lose access to the trip immediately.',
                    confirmLabel: 'Remove',
                  );
                  if (confirmed) {
                    await onRemoveMember(member.userId);
                  }
                  return;
                }
                if (targetRole == null || targetRole == member.role) return;
                final isDowngrade =
                    _roleRank(targetRole) < _roleRank(member.role);
                final title = targetRole == MemberRole.owner
                    ? 'Transfer ownership?'
                    : '${isDowngrade ? 'Downgrade' : 'Promote'} $displayName?';
                final body = targetRole == MemberRole.owner
                    ? 'This will make $displayName the trip owner.'
                    : 'Change role to ${_roleLabel(targetRole)}.';
                final confirmLabel =
                    targetRole == MemberRole.owner ? 'Transfer' : 'Confirm';
                if (isDowngrade || targetRole == MemberRole.owner) {
                  final confirmed = await _confirmMemberAction(
                    context,
                    title: title,
                    body: body,
                    confirmLabel: confirmLabel,
                  );
                  if (!confirmed) return;
                }
                await onUpdateRole(member.userId, targetRole);
              },
              itemBuilder: (context) {
                final items = <PopupMenuEntry<_MemberAction>>[];
                if (member.role != MemberRole.owner) {
                  items.add(
                    const PopupMenuItem(
                      value: _MemberAction.makeOwner,
                      child: Text('Make owner'),
                    ),
                  );
                }
                if (member.role != MemberRole.collaborator) {
                  items.add(
                    const PopupMenuItem(
                      value: _MemberAction.makeAdmin,
                      child: Text('Make admin'),
                    ),
                  );
                }
                if (member.role != MemberRole.viewer) {
                  items.add(
                    const PopupMenuItem(
                      value: _MemberAction.makeViewer,
                      child: Text('Make viewer'),
                    ),
                  );
                }
                if (member.role != MemberRole.owner) {
                  items.add(
                    const PopupMenuDivider(),
                  );
                  items.add(
                    const PopupMenuItem(
                      value: _MemberAction.remove,
                      child: Text('Remove'),
                    ),
                  );
                }
                return items;
              },
            ),
        ],
      ),
    );
  }
}

enum _MemberAction { makeOwner, makeAdmin, makeViewer, remove }

int _roleRank(MemberRole role) {
  switch (role) {
    case MemberRole.owner:
      return 3;
    case MemberRole.collaborator:
      return 2;
    case MemberRole.viewer:
      return 1;
  }
}

MemberRole? _roleForAction(_MemberAction action) {
  switch (action) {
    case _MemberAction.makeOwner:
      return MemberRole.owner;
    case _MemberAction.makeAdmin:
      return MemberRole.collaborator;
    case _MemberAction.makeViewer:
      return MemberRole.viewer;
    case _MemberAction.remove:
      return null;
  }
}

Future<bool> _confirmMemberAction(
  BuildContext context, {
  required String title,
  required String body,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

class _ChatBubble extends StatelessWidget {
  final ChatMessage message;
  final List<Member> members;
  final Map<String, UserProfile?> profiles;
  final String currentUserId;
  final bool showTimestamp;
  final VoidCallback onLongPress;
  final bool isPending;
  final bool isFailed;
  final VoidCallback? onRetry;

  const _ChatBubble({
    required this.message,
    required this.members,
    required this.profiles,
    required this.currentUserId,
    required this.showTimestamp,
    required this.onLongPress,
    this.isPending = false,
    this.isFailed = false,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final isMe = message.authorId == currentUserId;
    final author = members.firstWhere(
      (m) => m.userId == message.authorId,
      orElse: () => members.first,
    );
    final authorName = _displayNameForUser(
      userId: author.userId,
      fallback: author.name,
      profiles: profiles,
    );

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isFailed ? null : onLongPress,
        onTap: isFailed ? onRetry : null,
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isFailed
                ? const Color(0xFFFEE2E2)
                : isMe
                ? const Color(0xFF4F46E5)
                : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isFailed
                  ? const Color(0xFFFECACA)
                  : isMe
                  ? const Color(0xFF4F46E5)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          constraints: const BoxConstraints(maxWidth: 280),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                authorName,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isFailed
                      ? const Color(0xFFB91C1C)
                      : isMe
                      ? Colors.white70
                      : const Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message.text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isFailed
                      ? const Color(0xFF991B1B)
                      : isMe
                      ? Colors.white
                      : const Color(0xFF0F172A),
                ),
              ),
              if (isPending) ...[
                const SizedBox(height: 6),
                Text(
                  'Sending...',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
              if (isFailed) ...[
                const SizedBox(height: 6),
                Text(
                  'Failed to send. Tap to retry.',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: const Color(0xFFB91C1C),
                  ),
                ),
              ],
              if (showTimestamp) ...[
                const SizedBox(height: 6),
                Text(
                  _timeAgo(message.createdAt),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isMe ? Colors.white70 : const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineEmptyState extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const _InlineEmptyState({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 36,
            width: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Icon(icon, color: const Color(0xFF64748B), size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
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

class _AsyncErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _AsyncErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 44, color: Colors.red[400]),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteSheet extends StatelessWidget {
  final String? link;
  final String? error;
  final bool isLoading;
  final Invite? invite;
  final MemberRole role;
  final TextEditingController messageController;
  final ValueChanged<MemberRole> onRoleChanged;
  final VoidCallback onCreate;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback? onShowQr;

  const _InviteSheet({
    required this.link,
    required this.error,
    required this.isLoading,
    required this.invite,
    required this.role,
    required this.messageController,
    required this.onRoleChanged,
    required this.onCreate,
    required this.onCopy,
    required this.onShare,
    required this.onShowQr,
  });

  @override
  Widget build(BuildContext context) {
    final hasLink = link != null && link!.isNotEmpty;
    final status = invite == null
        ? (hasLink ? 'Generated just now' : 'No invite yet')
        : (invite!.isUsed ? 'Used' : 'Unused');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Invite collaborators',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          "They'll join your trip and collaborate.",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: const Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _StatusBadge(
              label: status,
              tone: const Color(0xFFF1F5F9),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: onShowQr,
              icon: const Icon(Icons.qr_code_2, size: 18),
              label: const Text('QR code'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Invite role',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Viewer'),
              selected: role == MemberRole.viewer,
              onSelected: (_) => onRoleChanged(MemberRole.viewer),
            ),
            ChoiceChip(
              label: const Text('Editor'),
              selected: role == MemberRole.collaborator,
              onSelected: (_) => onRoleChanged(MemberRole.collaborator),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: messageController,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'Optional message',
            hintText: 'Add a note for your travelers',
          ),
        ),
        if (hasLink) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.link, size: 16, color: Color(0xFF475569)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    link!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
          ),
        ],
        if (error != null) ...[
          const SizedBox(height: 10),
          Text(
            error!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFFDC2626),
            ),
          ),
        ],
        const SizedBox(height: 12),
        if (isLoading)
          Row(
            children: [
              const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Text(
                'Generating invite link...',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          )
        else
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: onCreate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF0F172A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(hasLink ? 'Refresh link' : 'Create link'),
                ),
              ),
              const SizedBox(width: 10),
              IconButton(
                tooltip: 'Copy invite link',
                onPressed: hasLink ? onCopy : null,
                icon: const Icon(Icons.copy, color: Color(0xFF4F46E5)),
              ),
              IconButton(
                tooltip: 'Share invite link',
                onPressed: hasLink ? onShare : null,
                icon: const Icon(Icons.share_outlined, color: Color(0xFF4F46E5)),
              ),
            ],
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _PlannerLoading extends StatelessWidget {
  const _PlannerLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: const [
        _PulseBox(height: 16, width: 180, radius: 10),
        SizedBox(height: 12),
        _PulseBox(height: 44, width: double.infinity, radius: 20),
        SizedBox(height: 16),
        _PulseBox(height: 120, width: double.infinity, radius: 18),
        SizedBox(height: 12),
        _PulseBox(height: 120, width: double.infinity, radius: 18),
      ],
    );
  }
}

class _TripDetailLoading extends StatelessWidget {
  const _TripDetailLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: const [
        Padding(
          padding: EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: _PulseBox(height: 220, width: double.infinity, radius: 24),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 20),
          child: _PulseBox(height: 44, width: double.infinity, radius: 18),
        ),
        SizedBox(height: 16),
        Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                _PulseBox(height: 120, width: double.infinity, radius: 18),
                SizedBox(height: 12),
                _PulseBox(height: 120, width: double.infinity, radius: 18),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PulseBox extends StatefulWidget {
  final double height;
  final double width;
  final double radius;

  const _PulseBox({
    required this.height,
    required this.width,
    required this.radius,
  });

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox> {
  late Timer _timer;
  bool _bright = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 900), (_) {
      if (!mounted) return;
      setState(() => _bright = !_bright);
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _bright ? const Color(0xFFF1F5F9) : const Color(0xFFE2E8F0);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 800),
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;
  final String? photoUrl;

  const _Avatar({required this.initials, this.photoUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      width: 36,
      decoration: const BoxDecoration(
        color: Color(0xFFE2E8F0),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: photoUrl == null
          ? Text(
              initials,
              style: Theme.of(
                context,
              ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
            )
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: photoUrl!,
                fit: BoxFit.cover,
                width: 36,
                height: 36,
              ),
            ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color tone;

  const _StatusBadge({required this.label, required this.tone});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}


class _Pill extends StatelessWidget {
  final IconData? icon;
  final String label;
  final Color background;
  final Color foreground;

  const _Pill({
    required this.icon,
    required this.label,
    this.background = const Color(0xFFF1F5F9),
    this.foreground = const Color(0xFF475569),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

int _completionProgress(List<ItineraryItem> items) {
  if (items.isEmpty) return 0;
  final done = items.where((i) => i.status == ItineraryStatus.done).length;
  return ((done / items.length) * 100).round();
}

int _compareItineraryItems(ItineraryItem a, ItineraryItem b) {
  final sectionCompare =
      _sectionOrder(a.section).compareTo(_sectionOrder(b.section));
  if (sectionCompare != 0) return sectionCompare;
  if (a.isTimeSet != b.isTimeSet) {
    return a.isTimeSet ? -1 : 1;
  }
  final orderCompare = a.order.compareTo(b.order);
  if (orderCompare != 0) return orderCompare;
  final timeCompare = a.dateTime.compareTo(b.dateTime);
  if (timeCompare != 0) return timeCompare;
  return a.createdAt.compareTo(b.createdAt);
}

Future<void> _openInMaps(BuildContext context, String location) async {
  final encoded = Uri.encodeComponent(location);
  final url = Platform.isIOS
      ? 'http://maps.apple.com/?q=$encoded'
      : 'https://www.google.com/maps/search/?api=1&query=$encoded';
  final uri = Uri.parse(url);
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open maps')),
    );
  }
}

Uri _normalizeUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return Uri.parse(trimmed);
  }
  return Uri.parse('https://$trimmed');
}

Future<void> _openExternalLink(BuildContext context, String link) async {
  final uri = _normalizeUrl(link);
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unable to open link')),
    );
  }
}

Map<int, List<ItineraryItem>> _groupItemsByDay(
  Trip trip,
  List<ItineraryItem> items,
) {
  final map = <int, List<ItineraryItem>>{};
  for (final item in items) {
    final daysDiff = item.dateTime.difference(trip.startDate).inDays;
    if (daysDiff >= 0 && daysDiff < trip.durationDays) {
      map.putIfAbsent(daysDiff, () => []).add(item);
    }
  }
  map.forEach((_, dayItems) {
    dayItems.sort(_compareItineraryItems);
  });
  return map;
}

Map<ItinerarySection, List<ItineraryItem>> _groupItemsBySection(
  List<ItineraryItem> items,
) {
  final map = <ItinerarySection, List<ItineraryItem>>{
    for (final section in ItinerarySection.values) section: <ItineraryItem>[],
  };
  for (final item in items) {
    map[item.section]?.add(item);
  }
  map.forEach((_, sectionItems) {
    sectionItems.sort(_compareItineraryItems);
  });
  return map;
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

String _labelForSection(ItinerarySection section) {
  switch (section) {
    case ItinerarySection.morning:
      return 'Morning';
    case ItinerarySection.afternoon:
      return 'Afternoon';
    case ItinerarySection.evening:
      return 'Evening';
  }
}

ItinerarySection _defaultSectionForNow() {
  final hour = DateTime.now().hour;
  if (hour < 12) return ItinerarySection.morning;
  if (hour < 17) return ItinerarySection.afternoon;
  return ItinerarySection.evening;
}

TimeOfDay _defaultTimeForSection(ItinerarySection section) {
  switch (section) {
    case ItinerarySection.morning:
      return const TimeOfDay(hour: 9, minute: 0);
    case ItinerarySection.afternoon:
      return const TimeOfDay(hour: 14, minute: 0);
    case ItinerarySection.evening:
      return const TimeOfDay(hour: 19, minute: 0);
  }
}

List<String> _parseCommaList(String raw) {
  return raw
      .split(',')
      .map((entry) => entry.trim())
      .where((entry) => entry.isNotEmpty)
      .toList();
}

String _defaultCategoryId(List<ItineraryCategory> categories) {
  if (categories.isEmpty) return 'activity';
  return categories.first.id;
}

final List<ItineraryCategory> _fallbackCategories = const [
  ItineraryCategory(id: 'flight', label: 'Flight', icon: 'flight', order: 0),
  ItineraryCategory(id: 'lodging', label: 'Lodging', icon: 'hotel', order: 1),
  ItineraryCategory(id: 'food', label: 'Food', icon: 'food', order: 2),
  ItineraryCategory(id: 'activity', label: 'Activity', icon: 'activity', order: 3),
  ItineraryCategory(
    id: 'transport',
    label: 'Transport',
    icon: 'transport',
    order: 4,
  ),
  ItineraryCategory(id: 'note', label: 'Note', icon: 'note', order: 5),
  ItineraryCategory(id: 'other', label: 'Other', icon: 'other', order: 6),
];

String _formatDateRange(Trip trip) {
  final dateFormat = DateFormat('MMM d');
  return '${dateFormat.format(trip.startDate)} - ${dateFormat.format(trip.endDate)}';
}

String _visibilityLabel(TripVisibility visibility) {
  switch (visibility) {
    case TripVisibility.inviteOnly:
      return 'Private link';
    case TripVisibility.friendsOnly:
      return 'Friends-only';
    case TripVisibility.public:
      return 'Public';
  }
}

String _roleLabel(MemberRole role) {
  switch (role) {
    case MemberRole.owner:
      return 'Owner';
    case MemberRole.collaborator:
      return 'Admin';
    case MemberRole.viewer:
      return 'Viewer';
  }
}

String _roleSummary(String roleLabel) {
  switch (roleLabel) {
    case 'Owner':
      return 'Full control of privacy, roles, and invites.';
    case 'Admin':
      return 'Can edit the itinerary, post updates, and invite others.';
    case 'Viewer':
      return 'View-only access. Request an upgrade to edit or post.';
    default:
      return 'Request access to collaborate on this trip.';
  }
}

TripPrivacyOption _privacyOptionForTrip(Trip trip) {
  switch (trip.audience.visibility) {
    case TripVisibility.inviteOnly:
      return TripPrivacyOption.privateLink;
    case TripVisibility.friendsOnly:
      return TripPrivacyOption.friendsOnly;
    case TripVisibility.public:
      return TripPrivacyOption.public;
  }
}

String _privacyLabel(TripPrivacyOption option) {
  switch (option) {
    case TripPrivacyOption.privateLink:
      return 'Private link';
    case TripPrivacyOption.friendsOnly:
      return 'Friends-only';
    case TripPrivacyOption.public:
      return 'Public';
  }
}

String _privacyDescription(TripPrivacyOption option) {
  switch (option) {
    case TripPrivacyOption.privateLink:
      return 'Only invited people can see the trip. No join requests.';
    case TripPrivacyOption.friendsOnly:
      return 'Friends can request to join and be approved by the owner.';
    case TripPrivacyOption.public:
      return 'Anyone can request to join with owner approval.';
  }
}

class _RoleGuideCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RoleGuideRow(
            label: 'Owner',
            description: 'Full control of privacy, roles, and invites.',
          ),
          const SizedBox(height: 8),
          _RoleGuideRow(
            label: 'Admin',
            description: 'Edit itinerary, post updates, and invite others.',
          ),
          const SizedBox(height: 8),
          _RoleGuideRow(
            label: 'Viewer',
            description: 'View-only access; request upgrade to edit or post.',
          ),
        ],
      ),
    );
  }
}

class _RoleGuideRow extends StatelessWidget {
  final String label;
  final String description;

  const _RoleGuideRow({required this.label, required this.description});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        Expanded(
          child: Text(
            description,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
        ),
      ],
    );
  }
}

int? _todayIndex(Trip trip) {
  final today = DateTime.now();
  final todayDate = DateTime(today.year, today.month, today.day);
  final startDate = DateTime(
    trip.startDate.year,
    trip.startDate.month,
    trip.startDate.day,
  );
  final endDate = DateTime(
    trip.endDate.year,
    trip.endDate.month,
    trip.endDate.day,
  );
  if (todayDate.isBefore(startDate) || todayDate.isAfter(endDate)) return null;
  return todayDate.difference(startDate).inDays;
}

String _initials(String name) {
  final parts = name.split(' ').where((p) => p.trim().isNotEmpty).toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24) return '${diff.inHours}h';
  return '${diff.inDays}d';
}

String _joinStatusCopy(JoinRequestStatus status) {
  switch (status) {
    case JoinRequestStatus.pending:
      return 'Waiting for a host to approve your request.';
    case JoinRequestStatus.approved:
      return 'Approved. You now have access to this trip.';
    case JoinRequestStatus.declined:
      return 'Declined. You can ask the host again later.';
  }
}


String _displayNameForUser({
  required String userId,
  required String fallback,
  required Map<String, UserProfile?> profiles,
}) {
  final profile = profiles[userId];
  final name = profile?.displayName ?? '';
  if (name.trim().isNotEmpty) {
    return name;
  }
  return fallback;
}

String? _photoUrlForUser({
  required String userId,
  required String? fallback,
  required Map<String, UserProfile?> profiles,
}) {
  return profiles[userId]?.photoUrl ?? fallback;
}

ItineraryCategory _categoryForItem(
  ItineraryItem item,
  List<ItineraryCategory> categories,
) {
  final resolved = categories.isEmpty ? _fallbackCategories : categories;
  final id = item.categoryId;
  if (id != null) {
    final match = resolved.where((entry) => entry.id == id).toList();
    if (match.isNotEmpty) return match.first;
  }
  final legacy = _legacyCategoryIdForType(item.type);
  final match = resolved.where((entry) => entry.id == legacy).toList();
  if (match.isNotEmpty) return match.first;
  return resolved.first;
}

IconData _iconForCategory(ItineraryCategory category) {
  switch (category.icon) {
    case 'flight':
      return Icons.flight_takeoff;
    case 'hotel':
      return Icons.hotel_outlined;
    case 'food':
      return Icons.restaurant_outlined;
    case 'activity':
      return Icons.camera_alt_outlined;
    case 'transport':
      return Icons.directions_transit_outlined;
    case 'note':
      return Icons.note_outlined;
    case 'other':
    default:
      return Icons.more_horiz;
  }
}

String _legacyCategoryIdForType(ItineraryItemType type) {
  switch (type) {
    case ItineraryItemType.flight:
      return 'flight';
    case ItineraryItemType.stay:
    case ItineraryItemType.lodging:
      return 'lodging';
    case ItineraryItemType.food:
      return 'food';
    case ItineraryItemType.activity:
      return 'activity';
    case ItineraryItemType.transport:
      return 'transport';
    case ItineraryItemType.note:
      return 'note';
    case ItineraryItemType.other:
      return 'other';
  }
}

String _labelForStatus(ItineraryStatus status) {
  switch (status) {
    case ItineraryStatus.planned:
      return 'Planned';
    case ItineraryStatus.booked:
      return 'Booked';
    case ItineraryStatus.done:
      return 'Done';
  }
}

LinearGradient _gradientForTrip(Trip trip) {
  final gradients = [
    const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)]),
    const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF14B8A6)]),
    const LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEF4444)]),
    const LinearGradient(colors: [Color(0xFFA855F7), Color(0xFFEC4899)]),
    const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFF84CC16)]),
  ];
  final index = trip.coverGradientId != null
      ? trip.coverGradientId!.clamp(0, gradients.length - 1)
      : trip.id.hashCode.abs() % gradients.length;
  return gradients[index];
}

