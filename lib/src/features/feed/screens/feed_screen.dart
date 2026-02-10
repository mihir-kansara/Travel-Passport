import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_application_trial/src/app_config.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/features/trips/screens/trip_detail_screen.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/utils/invite_utils.dart';
import 'package:flutter_application_trial/src/utils/profile_utils.dart';
import 'package:flutter_application_trial/src/widgets/empty_state_card.dart';
import 'package:flutter_application_trial/src/widgets/loading_placeholder.dart';
import 'package:flutter_application_trial/src/widgets/primary_button.dart';
import 'package:flutter_application_trial/src/widgets/secondary_button.dart';
import 'package:flutter_application_trial/src/widgets/trip_card.dart';

enum HomeTab { wall, trips }

typedef TripOpenCallback =
    void Function(Trip trip, {TripDetailTab? initialTab});

class FeedScreen extends ConsumerStatefulWidget {
  final HomeTab initialTab;

  const FeedScreen({super.key, this.initialTab = HomeTab.wall});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  late HomeTab _activeTab;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
  }

  @override
  void didUpdateWidget(covariant FeedScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialTab != widget.initialTab) {
      _activeTab = widget.initialTab;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tripsAsync = ref.watch(userTripsProvider);
    final session = ref.watch(authSessionProvider).value;
    final profile = ref.watch(currentUserProfileProvider).value;
    final showProfileBanner =
        session != null &&
        (profile == null || !isValidDisplayName(profile.displayName));

    return tripsAsync.when(
      data: (trips) => _buildContent(context, trips, showProfileBanner),
      loading: () => const LoadingPlaceholder(itemCount: 5, itemHeight: 180),
      error: (e, st) => Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red[400]),
            const SizedBox(height: AppSpacing.lg),
            Text('Error loading trips: $e'),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    List<Trip> trips,
    bool showProfileBanner,
  ) {
    final wallTrips = trips.where((t) => t.story.publishToWall).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final drafts = trips.where((t) => !t.isPublished).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final upcoming = trips.where((t) => t.isPublished && !t.isPast).toList()
      ..sort((a, b) => a.startDate.compareTo(b.startDate));
    final past = trips.where((t) => t.isPublished && t.isPast).toList()
      ..sort((a, b) => b.endDate.compareTo(a.endDate));
    final liveStories = wallTrips.where((t) => t.story.isLive).toList();
    final wallCount = wallTrips.length;
    final tripsCount = drafts.length + upcoming.length + past.length;

    return RefreshIndicator(
      onRefresh: () async => ref.refresh(userTripsProvider),
      child: ListView(
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          _HomeHeader(onCreate: _openCreateTrip, onJoin: _openJoinByToken),
          if (showProfileBanner)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _ProfileCompletionBanner(),
            ),
          if (liveStories.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _LiveRow(trips: liveStories, onOpenStory: _openStory),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _HomeTabs(
              activeTab: _activeTab,
              wallCount: wallCount,
              tripsCount: tripsCount,
              onChanged: _onPrimaryTabChanged,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(0, 0.04),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _activeTab == HomeTab.wall
                ? _WallFeed(
                    key: const ValueKey('wall'),
                    trips: wallTrips,
                    onOpenStory: _openStory,
                    onPublishStory: _goToTripsTab,
                    onOpenTrip: _openTrip,
                  )
                : _TripsFeed(
                    key: const ValueKey('trips'),
                    drafts: drafts,
                    upcoming: upcoming,
                    past: past,
                    onOpenTrip: _openTrip,
                    onOpenStory: _openStory,
                    onCreateTrip: _openCreateTrip,
                  ),
          ),
        ],
      ),
    );
  }

  void _goToTripsTab() {
    if (!mounted) return;
    context.go('/trips');
  }

  void _onPrimaryTabChanged(HomeTab tab) {
    if (!mounted) return;
    if (tab == HomeTab.wall) {
      context.go('/home');
    } else {
      context.go('/trips');
    }
  }

  void _openTrip(Trip trip, {TripDetailTab? initialTab}) {
    final tab = initialTab ?? TripDetailTab.planner;
    context.push('/trips/${trip.id}?tab=${tab.toQueryValue()}');
  }

  void _openStory(Trip trip) {
    context.push('/trips/${trip.id}/story');
  }

  void _openCreateTrip() {
    context.push('/trips/create');
  }

  Future<void> _openJoinByToken() async {
    final controller = TextEditingController();
    final token = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Join a trip'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Paste invite token or link',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.isEmpty) return;
              Navigator.pop(context, value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (!mounted || token == null || token.isEmpty) return;
    final parsedToken = parseInviteTokenFromText(token);
    if (parsedToken == null) {
      showGuardedSnackBar(context, 'Paste a valid invite token or link.');
      return;
    }
    context.push('/invite/$parsedToken');
  }
}

class _HomeHeader extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onJoin;

  const _HomeHeader({required this.onCreate, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppConfig.appName,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Plan together. Share like a story.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 240),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SecondaryButton(
                  label: 'Join a trip',
                  icon: Icons.link,
                  onPressed: onJoin,
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: 'Create a trip',
                  icon: Icons.add,
                  onPressed: onCreate,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCompletionBanner extends StatelessWidget {
  const _ProfileCompletionBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.person_outline, color: AppColors.primary),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Complete your profile',
                  style: Theme.of(
                    context,
                  ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Add a display name so collaborators recognize you.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.mutedText),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          TextButton(
            onPressed: () {
              context.push('/profile/setup');
            },
            child: const Text('Finish'),
          ),
        ],
      ),
    );
  }
}

class _HomeTabs extends StatelessWidget {
  final HomeTab activeTab;
  final int wallCount;
  final int tripsCount;
  final ValueChanged<HomeTab> onChanged;

  const _HomeTabs({
    required this.activeTab,
    required this.wallCount,
    required this.tripsCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: BorderRadius.circular(AppRadii.md),
      ),
      child: Row(
        children: [
          _TabButton(
            label: 'Wall',
            count: wallCount,
            isActive: activeTab == HomeTab.wall,
            onTap: () => onChanged(HomeTab.wall),
          ),
          _TabButton(
            label: 'Trips',
            count: tripsCount,
            isActive: activeTab == HomeTab.trips,
            onTap: () => onChanged(HomeTab.trips),
          ),
        ],
      ),
    );
  }
}

class _TabButton extends StatelessWidget {
  final String label;
  final int count;
  final bool isActive;
  final VoidCallback onTap;

  const _TabButton({
    required this.label,
    required this.count,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadii.md),
        child: Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isActive ? AppColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.md),
            boxShadow: isActive
                ? const [
                    BoxShadow(
                      color: Color(0x1A0F172A),
                      blurRadius: 8,
                      offset: Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isActive ? AppColors.text : AppColors.mutedText,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isActive
                      ? AppColors.placeholderAlt
                      : AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadii.pill),
                ),
                child: Text(
                  count.toString(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: isActive ? AppColors.text : AppColors.mutedText,
                  ),
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 6),
                Container(
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
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

class _LiveRow extends StatelessWidget {
  final List<Trip> trips;
  final ValueChanged<Trip> onOpenStory;

  const _LiveRow({required this.trips, required this.onOpenStory});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Live now',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppColors.subtleText,
              ),
            ),
            Text(
              '${trips.length} trip${trips.length == 1 ? '' : 's'}',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.subtleText),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: trips.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AppSpacing.md),
            itemBuilder: (context, index) {
              final trip = trips[index];
              return _StoryTile(trip: trip, onTap: () => onOpenStory(trip));
            },
          ),
        ),
      ],
    );
  }
}

class _StoryTile extends StatelessWidget {
  final Trip trip;
  final VoidCallback onTap;

  const _StoryTile({required this.trip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        width: 140,
        height: 140,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 82,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.md),
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
                    top: Radius.circular(AppRadii.md),
                  ),
                  color: Colors.black.withValues(alpha: 0.15),
                ),
                padding: const EdgeInsets.all(AppSpacing.md),
                alignment: Alignment.topLeft,
                child: Row(
                  children: [
                    Container(
                      height: 8,
                      width: 8,
                      decoration: const BoxDecoration(
                        color: Color(0xFF34D399),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      'Live',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    trip.destination,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '${trip.members.length} travelers',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppColors.subtleText,
                    ),
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

class _WallFeed extends StatelessWidget {
  final List<Trip> trips;
  final ValueChanged<Trip> onOpenStory;
  final VoidCallback onPublishStory;
  final TripOpenCallback onOpenTrip;

  const _WallFeed({
    super.key,
    required this.trips,
    required this.onOpenStory,
    required this.onPublishStory,
    required this.onOpenTrip,
  });

  @override
  Widget build(BuildContext context) {
    if (trips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: EmptyStateCard(
          title: 'No stories yet',
          subtitle: 'Publish a trip story to make your wall come alive.',
          icon: Icons.wallpaper,
          actionLabel: 'Publish a trip story',
          onAction: onPublishStory,
        ),
      );
    }

    return Column(
      children: trips
          .map(
            (trip) => Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                0,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: TripCard(
                trip: trip,
                onTap: () => onOpenStory(trip),
                onPlanner: () =>
                    onOpenTrip(trip, initialTab: TripDetailTab.planner),
                onStory: () => onOpenStory(trip),
                onInvite: () =>
                    onOpenTrip(trip, initialTab: TripDetailTab.people),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _TripsFeed extends StatelessWidget {
  final List<Trip> drafts;
  final List<Trip> upcoming;
  final List<Trip> past;
  final TripOpenCallback onOpenTrip;
  final ValueChanged<Trip> onOpenStory;
  final VoidCallback onCreateTrip;

  const _TripsFeed({
    super.key,
    required this.drafts,
    required this.upcoming,
    required this.past,
    required this.onOpenTrip,
    required this.onOpenStory,
    required this.onCreateTrip,
  });

  @override
  Widget build(BuildContext context) {
    final isEmpty = drafts.isEmpty && upcoming.isEmpty && past.isEmpty;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: isEmpty
          ? EmptyStateCard(
              title: 'Create your first trip',
              subtitle: 'Plan something new and invite your travel crew.',
              icon: Icons.flight_takeoff,
              actionLabel: 'Start a trip',
              onAction: onCreateTrip,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (drafts.isNotEmpty) ...[
                  Text(
                    'Drafts',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: AppColors.subtleText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  ...drafts.map(
                    (trip) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: TripCard(
                        trip: trip,
                        isDraft: true,
                        onTap: () => onOpenTrip(trip),
                        onPlanner: () =>
                            onOpenTrip(trip, initialTab: TripDetailTab.planner),
                        onStory: () => onOpenStory(trip),
                        onInvite: () =>
                            onOpenTrip(trip, initialTab: TripDetailTab.people),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                Text(
                  'Upcoming',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.subtleText,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (upcoming.isEmpty)
                  EmptyStateCard(
                    title: 'No upcoming trips',
                    subtitle:
                        'Start a trip and invite your crew to plan together.',
                    icon: Icons.flight_takeoff,
                    actionLabel: 'Start a trip',
                    onAction: onCreateTrip,
                  )
                else
                  ...upcoming.map(
                    (trip) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: TripCard(
                        trip: trip,
                        onTap: () => onOpenTrip(trip),
                        onPlanner: () =>
                            onOpenTrip(trip, initialTab: TripDetailTab.planner),
                        onStory: () => onOpenStory(trip),
                        onInvite: () =>
                            onOpenTrip(trip, initialTab: TripDetailTab.people),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  'Past',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppColors.subtleText,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (past.isEmpty)
                  EmptyStateCard(
                    title: 'No past trips yet',
                    subtitle:
                        'Your travel memories will collect here over time.',
                    icon: Icons.archive_outlined,
                    actionLabel: 'Start a trip',
                    onAction: onCreateTrip,
                  )
                else
                  ...past.map(
                    (trip) => Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: TripCard(
                        trip: trip,
                        muted: true,
                        onTap: () => onOpenTrip(trip),
                        onPlanner: () =>
                            onOpenTrip(trip, initialTab: TripDetailTab.planner),
                        onStory: () => onOpenStory(trip),
                        onInvite: () =>
                            onOpenTrip(trip, initialTab: TripDetailTab.people),
                      ),
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
    );
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
