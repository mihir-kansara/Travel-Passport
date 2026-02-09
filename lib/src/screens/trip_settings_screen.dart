import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_trial/src/app_config.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/widgets/buttons.dart';
import 'package:flutter_application_trial/src/widgets/section_header.dart';

class TripSettingsScreen extends ConsumerStatefulWidget {
  final String tripId;

  const TripSettingsScreen({super.key, required this.tripId});

  @override
  ConsumerState<TripSettingsScreen> createState() => _TripSettingsScreenState();
}

class _TripSettingsScreenState extends ConsumerState<TripSettingsScreen> {
  final _destinationController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _heroController = TextEditingController();
  final _headlineController = TextEditingController();
  final _highlightsController = TextEditingController();
  DateTimeRange? _dateRange;
  TripVisibility _visibility = TripVisibility.inviteOnly;
  bool _isSaving = false;
  bool _initialized = false;
  String? _inviteLink;
  bool _inviteLoading = false;
  bool _isDangerBusy = false;
  bool _isPublishing = false;

  @override
  void dispose() {
    _destinationController.dispose();
    _descriptionController.dispose();
    _heroController.dispose();
    _headlineController.dispose();
    _highlightsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tripAsync = ref.watch(tripByIdProvider(widget.tripId));

    return AppScaffold(
      title: 'Trip settings',
      onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      body: tripAsync.when(
        data: (trip) {
          if (trip == null) {
            return const Center(child: Text('Trip not found'));
          }
          if (!_initialized) {
            _initializeFromTrip(trip);
          }
          return ListView(
            children: [
              const SectionHeader(
                title: 'Basics',
                subtitle: 'Destination, dates, and audience.',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _destinationController,
                decoration: _inputDecoration('Destination', 'Kyoto, Japan'),
              ),
              const SizedBox(height: AppSpacing.lg),
              InkWell(
                onTap: _isSaving ? null : _pickDates,
                borderRadius: BorderRadius.circular(AppRadii.md),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                    vertical: AppSpacing.lg,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_today_outlined, size: 18),
                      const SizedBox(width: AppSpacing.sm),
                      Text(_dateLabel()),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<TripVisibility>(
                    value: _visibility,
                    onChanged: _isSaving
                        ? null
                        : (value) {
                            if (value == null) return;
                            setState(() => _visibility = value);
                          },
                    items: TripVisibility.values
                        .map(
                          (visibility) => DropdownMenuItem(
                            value: visibility,
                            child: Text(_visibilityLabel(visibility)),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader(
                title: 'Cover & story',
                subtitle: 'Headline and highlights for the story view.',
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _heroController,
                decoration: _inputDecoration('Cover photo URL', 'https://'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _headlineController,
                decoration: _inputDecoration('Story headline', 'Calm Kyoto'),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextField(
                controller: _highlightsController,
                decoration: _inputDecoration(
                  'Highlights',
                  'Sunrise hike, coffee, night market',
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader(
                title: 'Members',
                subtitle: 'Current trip collaborators.',
              ),
              const SizedBox(height: AppSpacing.lg),
              ...trip.members.map(
                (member) => Container(
                  margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: AppColors.border,
                        child: Text(
                          _initials(member.name),
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              member.name,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              member.role.name,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppColors.mutedText),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader(
                title: 'Sharing',
                subtitle: 'Publish to the wall and invite friends.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.public, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        'Publish to wall',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    Switch(
                      value: trip.story.publishToWall,
                      onChanged: _isPublishing || _isSaving
                          ? null
                          : (value) => _togglePublish(trip, value),
                      activeThumbColor: AppColors.primary,
                      activeTrackColor: const Color(0xFFC7D2FE),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(AppRadii.md),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invite link',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _inviteLink ?? 'Generate a fresh invite link.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.mutedText,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        TextButton(
                          onPressed: _inviteLoading
                              ? null
                              : () => _createInvite(trip),
                          child: Text(
                            _inviteLink == null ? 'Create link' : 'Refresh',
                          ),
                        ),
                        if (_inviteLink != null) ...[
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: _copyInvite,
                            child: const Text('Copy'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              const SectionHeader(
                title: 'Danger zone',
                subtitle: 'Leave or delete this trip.',
              ),
              const SizedBox(height: AppSpacing.lg),
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      label: 'Leave trip',
                      onPressed: _isDangerBusy ? null : () => _leaveTrip(trip),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: PrimaryButton(
                      label: 'Delete trip',
                      onPressed: _isDangerBusy ? null : () => _deleteTrip(trip),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              PrimaryButton(
                label: 'Save changes',
                isLoading: _isSaving,
                onPressed: _isSaving ? null : () => _saveTrip(trip),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('Error loading trip: $e')),
      ),
    );
  }

  void _initializeFromTrip(Trip trip) {
    _destinationController.text = trip.destination;
    _descriptionController.text = trip.description;
    _heroController.text = trip.heroImageUrl ?? '';
    _headlineController.text = trip.story.headline;
    _highlightsController.text = trip.story.highlights.join(', ');
    _dateRange = DateTimeRange(start: trip.startDate, end: trip.endDate);
    _visibility = trip.audience.visibility;
    _initialized = true;
  }

  String _dateLabel() {
    final range = _dateRange;
    if (range == null) return 'Pick dates';
    return '${DateFormat('MMM d').format(range.start)} - '
        '${DateFormat('MMM d').format(range.end)}';
  }

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final initialRange =
        _dateRange ??
        DateTimeRange(
          start: now.add(const Duration(days: 7)),
          end: now.add(const Duration(days: 10)),
        );
    final range = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: now.subtract(const Duration(days: 1)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (range == null) return;
    setState(() => _dateRange = range);
  }

  Future<void> _togglePublish(Trip trip, bool value) async {
    if (value) {
      final confirmed = await _showPublishPreview(trip);
      if (!confirmed) return;
    }
    if (!mounted) return;
    await runGuardedAsync(
      context: context,
      ref: ref,
      setBusy: (busy) => setState(() => _isPublishing = busy),
      errorMessage: 'Unable to update story visibility.',
      task: () async {
        final allowed = await ensureSignedIn(
          context,
          ref,
          message: 'Sign in to update story visibility.',
        );
        if (!allowed) return;
        final repo = ref.read(repositoryProvider);
        await repo.publishToWall(trip.id, value);
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
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

  Future<void> _createInvite(Trip trip) async {
    await runGuardedAsync(
      context: context,
      ref: ref,
      setBusy: (value) => setState(() => _inviteLoading = value),
      errorMessage: 'Unable to create invite link.',
      task: () async {
        final allowed = await ensureSignedIn(
          context,
          ref,
          message: 'Sign in to create an invite link.',
        );
        if (!allowed) return;
        final repo = ref.read(repositoryProvider);
        final invite = await repo.createInvite(tripId: trip.id);
        final link = AppConfig.inviteLink(invite.token);
        setState(() => _inviteLink = link);
        await Clipboard.setData(ClipboardData(text: link));
        if (!mounted) return;
        showGuardedSnackBar(context, 'Invite link copied');
      },
    );
  }

  Future<void> _copyInvite() async {
    if (_inviteLink == null) return;
    await Clipboard.setData(ClipboardData(text: _inviteLink!));
    if (!mounted) return;
    showGuardedSnackBar(context, 'Invite link copied');
  }

  Future<void> _saveTrip(Trip trip) async {
    if (_dateRange == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select trip dates.')));
      return;
    }
    await runGuardedAsync(
      context: context,
      ref: ref,
      setBusy: (value) => setState(() => _isSaving = value),
      successMessage: 'Trip updated',
      errorMessage: 'Unable to update trip',
      task: () async {
        final allowed = await ensureSignedIn(
          context,
          ref,
          message: 'Sign in to save trip updates.',
        );
        if (!allowed) return;
        final repo = ref.read(repositoryProvider);
        final updated = trip.copyWith(
          destination: _destinationController.text.trim(),
          description: _descriptionController.text.trim(),
          heroImageUrl: _heroController.text.trim().isEmpty
              ? null
              : _heroController.text.trim(),
          startDate: _dateRange!.start,
          endDate: _dateRange!.end,
          visibility: _visibility,
          audience: trip.audience.copyWith(visibility: _visibility),
          story: trip.story.copyWith(
            headline: _headlineController.text.trim(),
            highlights: _parseHighlights(),
          ),
        );
        await repo.updateTrip(updated);
        ref.invalidate(tripByIdProvider(trip.id));
        ref.invalidate(userTripsProvider);
      },
    );
  }

  List<String> _parseHighlights() {
    return _highlightsController.text
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList();
  }

  Future<void> _leaveTrip(Trip trip) async {
    await runGuardedAsync(
      context: context,
      ref: ref,
      setBusy: (value) => setState(() => _isDangerBusy = value),
      errorMessage: 'Unable to leave trip.',
      task: () async {
        final allowed = await ensureSignedIn(
          context,
          ref,
          message: 'Sign in to leave this trip.',
        );
        if (!allowed) return;
        final userId = ref.read(authSessionProvider).value?.userId;
        if (userId == null) return;
        final repo = ref.read(repositoryProvider);
        await repo.removeMember(trip.id, userId);
        ref.invalidate(userTripsProvider);
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  Future<void> _deleteTrip(Trip trip) async {
    await runGuardedAsync(
      context: context,
      ref: ref,
      setBusy: (value) => setState(() => _isDangerBusy = value),
      errorMessage: 'Unable to delete trip.',
      task: () async {
        final allowed = await ensureSignedIn(
          context,
          ref,
          message: 'Sign in to delete this trip.',
        );
        if (!allowed) return;
        final repo = ref.read(repositoryProvider);
        await repo.deleteTrip(trip.id);
        ref.invalidate(userTripsProvider);
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      },
    );
  }

  InputDecoration _inputDecoration(String label, String hint) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xFFF8FAFC),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.md),
        borderSide: BorderSide.none,
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return 'TP';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
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
