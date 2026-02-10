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
import 'package:flutter_application_trial/src/app_config.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/repositories/repository.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/features/trips/screens/trip_settings_screen.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/widgets/info_chip.dart';

enum TripDetailTab { planner, checklist, story, people, chat }

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(tripByIdProvider(widget.tripId));
    final itineraryAsync = ref.watch(tripItineraryProvider(widget.tripId));
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
                          selectedDayIndex: _selectedDayIndex,
                          onSelectDay: (index) =>
                              setState(() => _selectedDayIndex = index),
                          onAddItem: (type) =>
                              _openPlannerSheet(trip, items, type: type),
                          onEditItem: (item) =>
                              _openPlannerSheet(trip, items, item: item),
                          onEditNotes: (item) => _openNotesEditor(trip, item),
                          onDeleteItem: (item) =>
                              _handleDeleteItem(trip, item),
                          onToggleStatus: (item) =>
                              _handleToggleStatus(trip, item),
                            onOpenComments: (item) => _openItineraryComments(
                            trip,
                            item,
                            profiles,
                            ),
                          onReorderDay: (items) =>
                              _handleReorderDay(trip, items),
                        ),
                        loading: () => const _PlannerLoading(),
                        error: (e, st) => _AsyncErrorState(
                          message: 'Unable to load the itinerary.',
                          onRetry: () => ref.refresh(
                            tripItineraryProvider(widget.tripId),
                          ),
                        ),
                      ),
                      _ChecklistTab(
                        trip: trip,
                        profiles: profiles,
                        currentUserId: currentUserId,
                        onUpdateMember: _updateMemberChecklist,
                        onUpsertShared: _upsertSharedChecklistItem,
                        onDeleteShared: _deleteSharedChecklistItem,
                      ),
                      _StoryTab(
                        trip: trip,
                        profiles: profiles,
                        comments: commentsAsync.value ?? const [],
                        commentController: _commentController,
                        onSendComment: () => _handleSendComment(trip),
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
                        onInvite: () => _openInviteSheet(trip),
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
      authMessage: 'Sign in to comment on this story.',
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
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to send a message.',
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

  Future<bool> _updateMemberChecklist(
    Trip trip,
    MemberChecklist checklist,
  ) async {
    return _runTripAction(
      'checklist-member-${checklist.userId}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.updateMemberChecklist(trip.id, checklist);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update checklist items.',
      errorMessage: 'Unable to update checklist.',
    );
  }

  Future<bool> _upsertSharedChecklistItem(Trip trip, ChecklistItem item) async {
    return _runTripAction(
      'checklist-shared-${item.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.upsertSharedChecklistItem(trip.id, item);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update shared checklist items.',
      errorMessage: 'Unable to update shared checklist.',
    );
  }

  Future<bool> _deleteSharedChecklistItem(Trip trip, String itemId) async {
    return _runTripAction(
      'checklist-shared-delete-$itemId',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.deleteSharedChecklistItem(trip.id, itemId);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update shared checklist items.',
      errorMessage: 'Unable to delete shared checklist item.',
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
    await _runTripAction(
      'join-respond-$requestId',
      () async {
        HapticFeedback.selectionClick();
        final repo = ref.read(repositoryProvider);
        await repo.respondToJoinRequest(trip.id, requestId, status);
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to manage join requests.',
      errorMessage: 'Unable to update join request.',
    );
  }

  Future<void> _handlePublishToggle(Trip trip, bool value) async {
    if (value) {
      final confirmed = await _showPublishPreview(trip);
      if (!confirmed) return;
    }
    await _runTripAction(
      'publish-${trip.id}',
      () async {
        HapticFeedback.selectionClick();
        final repo = ref.read(repositoryProvider);
        await repo.publishToWall(trip.id, value);
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
      authMessage: 'Sign in to publish this story.',
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
                  ? trip.story.highlights.take(3).join(' · ')
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
      authMessage: 'Sign in to update story visibility.',
      errorMessage: 'Unable to update moment visibility.',
    );
  }

  Future<void> _handleToggleStatus(Trip trip, ItineraryItem item) async {
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
        ref.invalidate(tripItineraryProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update the planner.',
      errorMessage: 'Unable to update itinerary item.',
    );
  }

  Future<void> _handleDeleteItem(Trip trip, ItineraryItem item) async {
    await _runTripAction(
      'planner-delete-${item.id}',
      () async {
        HapticFeedback.selectionClick();
        final repo = ref.read(repositoryProvider);
        await repo.deleteItineraryItem(trip.id, item.id);
        ref.invalidate(tripItineraryProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update the planner.',
      errorMessage: 'Unable to delete itinerary item.',
    );
  }

  Future<void> _handleReorderDay(
    Trip trip,
    List<ItineraryItem> items,
  ) async {
    await _runTripAction(
      'planner-reorder-${trip.id}',
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.reorderItineraryItems(trip.id, items);
        ref.invalidate(tripItineraryProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update the planner.',
      errorMessage: 'Unable to reorder itinerary items.',
    );
  }

  Future<void> _openPlannerSheet(
    Trip trip,
    List<ItineraryItem> items, {
    ItineraryItemType? type,
    ItineraryItem? item,
  }) async {
    final titleController = TextEditingController(text: item?.title ?? '');
    final notesController = TextEditingController(
      text: item?.notes ?? item?.description ?? '',
    );
    final locationController = TextEditingController(
      text: item?.location ?? '',
    );
    final linkController = TextEditingController(text: item?.link ?? '');
    final date = trip.startDate.add(Duration(days: _selectedDayIndex));
    TimeOfDay time = item != null
        ? TimeOfDay.fromDateTime(item.dateTime)
        : const TimeOfDay(hour: 9, minute: 0);
    ItineraryItemType selectedType =
        item?.type ?? type ?? ItineraryItemType.activity;
    ItineraryStatus selectedStatus = item?.status ?? ItineraryStatus.planned;
    String? selectedAssigneeId = item?.assigneeId ?? item?.assignedTo;

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
                TextField(
                  controller: notesController,
                  decoration: const InputDecoration(labelText: 'Notes'),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: linkController,
                  decoration: const InputDecoration(labelText: 'Link'),
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
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<ItineraryItemType>(
                        initialValue: selectedType,
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => selectedType = value);
                        },
                        items: ItineraryItemType.values
                            .map(
                              (entry) => DropdownMenuItem(
                                value: entry,
                                child: Text(_labelForType(entry)),
                              ),
                            )
                            .toList(),
                        decoration: const InputDecoration(labelText: 'Section'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () async {
                        final picked = await showTimePicker(
                          context: context,
                          initialTime: time,
                        );
                        if (picked != null) {
                          setState(() => time = picked);
                        }
                      },
                      child: Text(time.format(context)),
                    ),
                  ],
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
                                    i.dateTime.day == date.day,
                              )
                              .map((i) => i.order)
                              .toList();
                          final maxOrder =
                              dayOrders.isEmpty ? -1 : dayOrders.reduce(
                                (a, b) => a > b ? a : b,
                              );
                          final order = item?.order ?? maxOrder + 1;
                          final dateTime = DateTime(
                            date.year,
                            date.month,
                            date.day,
                            time.hour,
                            time.minute,
                          );
                          final notesText = notesController.text.trim();
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
                              type: selectedType,
                              location: locationController.text.trim().isEmpty
                                  ? null
                                  : locationController.text.trim(),
                              link: linkController.text.trim().isEmpty
                                  ? null
                                  : linkController.text.trim(),
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
        ref.invalidate(tripItineraryProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update the planner.',
      errorMessage: 'Unable to save itinerary item.',
    );
  }

  Future<void> _openNotesEditor(Trip trip, ItineraryItem item) async {
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
        ref.invalidate(tripItineraryProvider(trip.id));
        ref.invalidate(tripByIdProvider(trip.id));
      },
      authMessage: 'Sign in to update the planner.',
      errorMessage: 'Unable to update notes.',
    );
  }

  Future<void> _openItineraryComments(
    Trip trip,
    ItineraryItem item,
    Map<String, UserProfile?> profiles,
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
          ),
        );
      },
    );
  }

  String _buildInviteLink(String token) {
    // TODO: Replace with Firebase Dynamic Links or short links when ready.
    return AppConfig.inviteLink(token);
  }

  Future<void> _handleCreateInvite(Trip trip) async {
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
        final invite = await repo.createInvite(tripId: trip.id);
        final link = _buildInviteLink(invite.token);
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        setState(() {
          _inviteLink = link;
          _lastInvite = invite;
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

  Future<void> _handleShareInvite() async {
    final link = _inviteLink;
    if (link == null) {
      showGuardedSnackBar(context, 'Create an invite link first.');
      return;
    }
    await Share.share('Join my trip and collaborate: $link');
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
            onCreate: () => _handleCreateInvite(trip),
            onCopy: _handleCopyInvite,
            onShare: _handleShareInvite,
          ),
        );
      },
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
  final int selectedDayIndex;
  final ValueChanged<int> onSelectDay;
  final ValueChanged<ItineraryItemType> onAddItem;
  final ValueChanged<ItineraryItem> onEditItem;
  final ValueChanged<ItineraryItem> onEditNotes;
  final ValueChanged<ItineraryItem> onDeleteItem;
  final ValueChanged<ItineraryItem> onToggleStatus;
  final ValueChanged<ItineraryItem> onOpenComments;
  final ValueChanged<List<ItineraryItem>> onReorderDay;

  const _PlannerTab({
    required this.trip,
    required this.items,
    required this.selectedDayIndex,
    required this.onSelectDay,
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
    final progress = _completionProgress(items);
    final todayIndex = _todayIndex(trip);
    final dayLabel = DateFormat('EEE, MMM d').format(days[selectedDayIndex]);
    final canJumpToToday =
        todayIndex != null && todayIndex != selectedDayIndex;

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
            SliverToBoxAdapter(
              child: const SizedBox(height: 12),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                child: _PlannerItineraryList(
                  dayItems: dayItemsSorted,
                  members: trip.members,
                  onEditItem: onEditItem,
                  onEditNotes: onEditNotes,
                  onDeleteItem: onDeleteItem,
                  onToggleStatus: onToggleStatus,
                  onOpenComments: onOpenComments,
                  onReorderDay: onReorderDay,
                ),
              ),
            ),
          ],
        ),
        Positioned(
          right: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _showAddItemSheet(context, onAddItem),
            icon: const Icon(Icons.add),
            label: const Text('Add'),
          ),
        ),
      ],
    );
  }

  Future<void> _showAddItemSheet(
    BuildContext context,
    ValueChanged<ItineraryItemType> onAddItem,
  ) async {
    final selected = await showModalBottomSheet<ItineraryItemType>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: ItineraryItemType.values.map((type) {
              return ListTile(
                leading: Icon(_iconForType(type)),
                title: Text(_labelForType(type)),
                onTap: () => Navigator.of(context).pop(type),
              );
            }).toList(),
          ),
        );
      },
    );
    if (selected != null) {
      onAddItem(selected);
    }
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
                'Day ${index + 1} · ${DateFormat('EEE, MMM d').format(date)}';
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
  final List<ItineraryItem> dayItems;
  final List<Member> members;
  final ValueChanged<ItineraryItem> onEditItem;
  final ValueChanged<ItineraryItem> onEditNotes;
  final ValueChanged<ItineraryItem> onDeleteItem;
  final ValueChanged<ItineraryItem> onToggleStatus;
  final ValueChanged<ItineraryItem> onOpenComments;
  final ValueChanged<List<ItineraryItem>> onReorderDay;

  const _PlannerItineraryList({
    required this.dayItems,
    required this.members,
    required this.onEditItem,
    required this.onEditNotes,
    required this.onDeleteItem,
    required this.onToggleStatus,
    required this.onOpenComments,
    required this.onReorderDay,
  });

  @override
  Widget build(BuildContext context) {
    if (dayItems.isEmpty) {
      return const _InlineEmptyState(
        title: 'No plans yet',
        subtitle: 'Add items for flights, stays, food, and more.',
        icon: Icons.event_note_outlined,
      );
    }

    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      itemCount: dayItems.length,
      onReorder: (oldIndex, newIndex) {
        if (newIndex > oldIndex) newIndex -= 1;
        final reordered = [...dayItems];
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
        final item = dayItems[index];
        return _PlannerItemCard(
          key: ValueKey(item.id),
          item: item,
          members: members,
          dragHandle: ReorderableDragStartListener(
            index: index,
            child: const Icon(
              Icons.drag_handle,
              size: 18,
              color: Color(0xFF94A3B8),
            ),
          ),
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
    final icon = _iconForType(item.type);
    final timeLabel = DateFormat('h:mm a').format(item.dateTime);
    final statusLabel = _labelForStatus(item.status);
    final notesText = (item.notes ?? item.description ?? '').trim();
    final hasNotes = notesText.isNotEmpty;
    final linkText = (item.link ?? '').trim();
    final hasLink = linkText.isNotEmpty;
    final locationText = (item.location ?? '').trim();
    final hasLocation = locationText.isNotEmpty;

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
                icon: icon,
                label: timeLabel,
              ),
              const SizedBox(width: 8),
              _Pill(
                icon: null,
                label: _labelForType(item.type),
                background: const Color(0xFFEFF6FF),
                foreground: const Color(0xFF1D4ED8),
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
                onPressed: widget.onEdit,
              ),
              IconButton(
                tooltip: 'Delete item',
                icon: const Icon(Icons.delete_outline, size: 18),
                color: const Color(0xFF475569),
                onPressed: widget.onDelete,
              ),
              IconButton(
                tooltip: 'Mark complete',
                icon: Icon(
                  item.status == ItineraryStatus.done
                      ? Icons.check_circle
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                onPressed: widget.onToggleStatus,
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
                    icon: Icons.link_outlined,
                    label: 'Open link',
                    background: const Color(0xFFF8FAFC),
                    foreground: const Color(0xFF475569),
                  ),
                ),
              TextButton.icon(
                onPressed: widget.onEditNotes,
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
        ],
      ),
    );
  }
}

class _ChecklistTab extends StatefulWidget {
  final Trip trip;
  final Map<String, UserProfile?> profiles;
  final String currentUserId;
  final Future<bool> Function(Trip, MemberChecklist) onUpdateMember;
  final Future<bool> Function(Trip, ChecklistItem) onUpsertShared;
  final Future<bool> Function(Trip, String) onDeleteShared;

  const _ChecklistTab({
    required this.trip,
    required this.profiles,
    required this.currentUserId,
    required this.onUpdateMember,
    required this.onUpsertShared,
    required this.onDeleteShared,
  });

  @override
  State<_ChecklistTab> createState() => _ChecklistTabState();
}

class _ChecklistTabState extends State<_ChecklistTab> {
  final TextEditingController _sharedController = TextEditingController();
  int _segmentIndex = 0;
  final Map<String, MemberChecklist> _memberOverrides = {};
  final Map<String, ChecklistItem> _sharedOverrides = {};

  @override
  void dispose() {
    _sharedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final trip = widget.trip;
    final sharedItems = [...trip.checklist.shared]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final isMine = _segmentIndex == 0;
    final currentMember = trip.members.firstWhere(
      (m) => m.userId == widget.currentUserId,
      orElse: () => trip.members.first,
    );
    final sharedById = {for (final item in sharedItems) item.id: item};
    for (final entry in _sharedOverrides.entries) {
      if (!sharedById.containsKey(entry.key)) {
        sharedItems.add(entry.value);
      }
    }
    for (var i = 0; i < sharedItems.length; i++) {
      final item = sharedItems[i];
      final override = _sharedOverrides[item.id];
      if (override != null) {
        sharedItems[i] = override;
      }
    }
    sharedItems.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Expanded(child: _ChecklistSegmentedControl(
              index: _segmentIndex,
              onChanged: (value) => setState(() => _segmentIndex = value),
            )),
            const SizedBox(width: 12),
            if (!isMine)
              ElevatedButton.icon(
                onPressed: () => _promptAddShared(context, trip),
                icon: const Icon(Icons.add),
                label: const Text('Add item'),
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
          _MemberChecklistCard(
            member: currentMember,
            profiles: widget.profiles,
            entry: _entryForMember(trip, currentMember.userId),
            canEdit: true,
            onChanged: (updated) => _updateMember(trip, updated),
          ),
        ] else ...[
          Text(
            'Shared logistics',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          if (sharedItems.isEmpty)
            const _InlineEmptyState(
              title: 'No shared tasks yet',
              subtitle: 'Add the group items everyone is waiting on.',
              icon: Icons.checklist_outlined,
            )
          else
            ...sharedItems.map(
              (item) => _SharedChecklistTile(
                item: item,
                onToggle: () => _toggleShared(trip, item),
                onDelete: () => _deleteShared(trip, item.id),
              ),
            ),
        ],
      ],
    );
  }

  MemberChecklist _entryForMember(Trip trip, String userId) {
    final override = _memberOverrides[userId];
    if (override != null) return override;
    try {
      return trip.checklist.members.firstWhere((m) => m.userId == userId);
    } catch (e) {
      return MemberChecklist(userId: userId, updatedAt: DateTime.now());
    }
  }

  Future<void> _updateMember(Trip trip, MemberChecklist updated) async {
    final previous = _entryForMember(trip, updated.userId);
    setState(() => _memberOverrides[updated.userId] = updated);
    final success = await widget.onUpdateMember(trip, updated);
    if (!mounted) return;
    if (success) {
      setState(() => _memberOverrides.remove(updated.userId));
    } else {
      setState(() => _memberOverrides[updated.userId] = previous);
    }
  }

  Future<void> _addShared(Trip trip, String title) async {
    if (title.isEmpty) return;
    final item = ChecklistItem(
      id: const Uuid().v4(),
      title: title,
      isDone: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    setState(() => _sharedOverrides[item.id] = item);
    final success = await widget.onUpsertShared(trip, item);
    if (!mounted) return;
    if (success) {
      setState(() => _sharedOverrides.remove(item.id));
    } else {
      setState(() => _sharedOverrides.remove(item.id));
    }
  }

  Future<void> _promptAddShared(BuildContext context, Trip trip) async {
    _sharedController.clear();
    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add shared item'),
          content: TextField(
            controller: _sharedController,
            decoration: const InputDecoration(hintText: 'Add a shared task'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () =>
                  Navigator.of(context).pop(_sharedController.text.trim()),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    if (title == null || title.isEmpty) return;
    await _addShared(trip, title);
  }

  Future<void> _toggleShared(Trip trip, ChecklistItem item) async {
    final updated = item.copyWith(
      isDone: !item.isDone,
      updatedAt: DateTime.now(),
    );
    final previous = _sharedOverrides[item.id] ?? item;
    setState(() => _sharedOverrides[item.id] = updated);
    final success = await widget.onUpsertShared(trip, updated);
    if (!mounted) return;
    if (success) {
      setState(() => _sharedOverrides.remove(item.id));
    } else {
      setState(() => _sharedOverrides[item.id] = previous);
    }
  }

  Future<void> _deleteShared(Trip trip, String itemId) async {
    await widget.onDeleteShared(trip, itemId);
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

class _MemberChecklistCard extends StatelessWidget {
  final Member member;
  final Map<String, UserProfile?> profiles;
  final MemberChecklist entry;
  final bool canEdit;
  final ValueChanged<MemberChecklist> onChanged;

  const _MemberChecklistCard({
    required this.member,
    required this.profiles,
    required this.entry,
    required this.canEdit,
    required this.onChanged,
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
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _Avatar(initials: _initials(displayName), photoUrl: photoUrl),
              const SizedBox(width: 12),
              Text(
                displayName,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _ChecklistToggle(
            label: 'Flight booked',
            value: entry.flightBooked,
            enabled: canEdit,
            onChanged: (value) => onChanged(
              entry.copyWith(flightBooked: value, updatedAt: DateTime.now()),
            ),
          ),
          _ChecklistToggle(
            label: 'Hotel booked',
            value: entry.hotelBooked,
            enabled: canEdit,
            onChanged: (value) => onChanged(
              entry.copyWith(hotelBooked: value, updatedAt: DateTime.now()),
            ),
          ),
          _ChecklistToggle(
            label: 'Reservations set',
            value: entry.reservationsBooked,
            enabled: canEdit,
            onChanged: (value) => onChanged(
              entry.copyWith(
                reservationsBooked: value,
                updatedAt: DateTime.now(),
              ),
            ),
          ),
          _ChecklistToggle(
            label: 'Passport ready',
            value: entry.passportReady,
            enabled: canEdit,
            onChanged: (value) => onChanged(
              entry.copyWith(passportReady: value, updatedAt: DateTime.now()),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistToggle extends StatelessWidget {
  final String label;
  final bool value;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  const _ChecklistToggle({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodySmall),
        ),
        Switch(
          value: value,
          onChanged: enabled ? onChanged : null,
          activeThumbColor: const Color(0xFF4F46E5),
          activeTrackColor: const Color(0xFFC7D2FE),
        ),
      ],
    );
  }
}

class _SharedChecklistTile extends StatelessWidget {
  final ChecklistItem item;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _SharedChecklistTile({
    required this.item,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Checkbox(value: item.isDone, onChanged: (_) => onToggle()),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              item.title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                decoration: item.isDone ? TextDecoration.lineThrough : null,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Delete item',
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: onDelete,
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
                    : () => onTogglePublish(true),
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
                      : () => onTogglePublish(false),
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
                          ? trip.story.highlights.take(3).join(' · ')
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
              onToggleVisibility: () => onToggleMoment(moment),
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
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
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
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: isSendingComment ? null : onSendComment,
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
  final VoidCallback onInvite;
  final bool isJoinRequestBusy;
  final bool Function(String requestId) isResponding;

  const _PeopleTab({
    required this.trip,
    required this.profiles,
    required this.onRequestJoin,
    required this.onRespondJoin,
    required this.currentUserId,
    required this.onInvite,
    required this.isJoinRequestBusy,
    required this.isResponding,
  });

  @override
  Widget build(BuildContext context) {
    final pending = trip.joinRequests
        .where((r) => r.status == JoinRequestStatus.pending)
        .toList();
    final isMember = trip.members.any((m) => m.userId == currentUserId);
    JoinRequest? myRequest;
    try {
      myRequest = trip.joinRequests.firstWhere(
        (r) => r.userId == currentUserId,
      );
    } catch (_) {}

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
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
              onPressed: onInvite,
              icon: const Icon(Icons.person_add_alt_outlined, size: 18),
              label: const Text('Invite'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...trip.members.map(
          (member) => _MemberTile(member: member, profiles: profiles),
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
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Send message',
                onPressed: widget.isSending ? null : widget.onSend,
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

  const _ItineraryCommentsSheet({
    required this.tripId,
    required this.item,
    required this.members,
    required this.profiles,
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
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: _isSending ? null : _sendComment,
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

  const _JoinRequestCard({
    required this.request,
    required this.members,
    required this.profiles,
    required this.onRespond,
    required this.isBusy,
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
                      : () => onRespond(request.id, JoinRequestStatus.approved),
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
                      : () => onRespond(request.id, JoinRequestStatus.declined),
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

  const _MemberTile({required this.member, required this.profiles});

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
                  roleLabel,
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
        ],
      ),
    );
  }
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
  final VoidCallback onCreate;
  final VoidCallback onCopy;
  final VoidCallback onShare;

  const _InviteSheet({
    required this.link,
    required this.error,
    required this.isLoading,
    required this.invite,
    required this.onCreate,
    required this.onCopy,
    required this.onShare,
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
            Text(
              'QR code (TODO)',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: const Color(0xFF94A3B8),
              ),
            ),
          ],
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
  final timeCompare = a.dateTime.compareTo(b.dateTime);
  if (timeCompare != 0) return timeCompare;
  final orderCompare = a.order.compareTo(b.order);
  if (orderCompare != 0) return orderCompare;
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

String _formatDateRange(Trip trip) {
  final dateFormat = DateFormat('MMM d');
  return '${dateFormat.format(trip.startDate)} - ${dateFormat.format(trip.endDate)}';
}

String _visibilityLabel(TripVisibility visibility) {
  switch (visibility) {
    case TripVisibility.inviteOnly:
      return 'Private';
    case TripVisibility.friendsOnly:
      return 'Friends';
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
      return 'Member';
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
IconData _iconForType(ItineraryItemType type) {
  switch (type) {
    case ItineraryItemType.flight:
      return Icons.flight_takeoff;
    case ItineraryItemType.transport:
      return Icons.directions_transit_outlined;
    case ItineraryItemType.activity:
      return Icons.camera_alt_outlined;
    case ItineraryItemType.stay:
      return Icons.hotel_outlined;
    case ItineraryItemType.lodging:
      return Icons.hotel_outlined;
    case ItineraryItemType.food:
      return Icons.restaurant_outlined;
    case ItineraryItemType.note:
      return Icons.note_outlined;
    case ItineraryItemType.other:
      return Icons.more_horiz;
  }
}

String _labelForType(ItineraryItemType type) {
  switch (type) {
    case ItineraryItemType.flight:
      return 'Flights';
    case ItineraryItemType.stay:
      return 'Lodging';
    case ItineraryItemType.lodging:
      return 'Lodging';
    case ItineraryItemType.food:
      return 'Food';
    case ItineraryItemType.activity:
      return 'Activities';
    case ItineraryItemType.transport:
      return 'Transport';
    case ItineraryItemType.note:
      return 'Notes';
    case ItineraryItemType.other:
      return 'Other';
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
