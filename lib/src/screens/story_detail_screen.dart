import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';

class StoryDetailScreen extends ConsumerStatefulWidget {
  final String tripId;

  const StoryDetailScreen({super.key, required this.tripId});

  @override
  ConsumerState<StoryDetailScreen> createState() => _StoryDetailScreenState();
}

class _StoryDetailScreenState extends ConsumerState<StoryDetailScreen> {
  final TextEditingController _commentController = TextEditingController();
  bool _isLiking = false;
  bool _isSendingComment = false;
  bool? _likeOverride;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final storyAsync = ref.watch(
      tripStreamProvider(widget.tripId).select((value) {
        return value.whenData((trip) {
          if (trip == null) return null;
          return _StoryPayload(
            storyId: trip.id,
            story: trip.story,
            members: trip.members,
            destination: trip.destination,
            heroImageUrl: trip.heroImageUrl,
            coverGradientId: trip.coverGradientId,
          );
        });
      }),
    );
    final currentUserId = ref.watch(authSessionProvider).value?.userId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Trip Story'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: storyAsync.when(
        data: (payload) {
          if (payload == null) {
            return const Center(child: Text('Story not found'));
          }
          final isLiked = _isTripLiked(payload.story, currentUserId);
          final likeCount = _likeCountForTrip(payload.story, currentUserId);
          return _StoryDetailBody(
            story: payload.story,
            members: payload.members,
            destination: payload.destination,
            heroImageUrl: payload.heroImageUrl,
            coverGradientId: payload.coverGradientId,
            commentController: _commentController,
            onLike: _isLiking
              ? null
              : () => _handleLike(payload.story, payload.storyId),
            onSendComment: _isSendingComment
                ? null
                : () => _handleSendComment(payload.storyId),
            isLiked: isLiked,
            likeCount: likeCount,
          );
        },
        loading: () => const _StoryDetailLoading(),
        error: (e, st) => _AsyncErrorState(
          message: 'Unable to load this story.',
          onRetry: () => ref.refresh(tripStreamProvider(widget.tripId)),
        ),
      ),
    );
  }

  bool _isTripLiked(TripStory story, String userId) {
    final baseLiked = story.likedBy.contains(userId);
    return _likeOverride ?? baseLiked;
  }

  int _likeCountForTrip(TripStory story, String userId) {
    final baseLiked = story.likedBy.contains(userId);
    final isLiked = _likeOverride ?? baseLiked;
    var count = story.wallStats.likes;
    if (isLiked && !baseLiked) count += 1;
    if (!isLiked && baseLiked) count -= 1;
    if (count < 0) count = 0;
    return count;
  }

  Future<void> _handleLike(TripStory story, String tripId) async {
    if (_isLiking) return;
    setState(() => _isLiking = true);
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to like this story.',
    );
    if (!mounted) return;
    if (!allowed) {
      if (mounted) setState(() => _isLiking = false);
      return;
    }
    final session = ref.read(authSessionProvider).value;
    if (session == null) {
      if (mounted) setState(() => _isLiking = false);
      return;
    }
    final previousOverride = _likeOverride;
    final previousLiked = _isTripLiked(story, session.userId);
    final nextLiked = !previousLiked;
    setState(() => _likeOverride = nextLiked);
    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.setTripLike(tripId, nextLiked);
      },
      errorMessage: 'Unable to update like.',
    );
    if (!mounted) return;
    if (!success) {
      setState(() => _likeOverride = previousOverride);
    }
    setState(() => _isLiking = false);
  }

  Future<void> _handleSendComment(String tripId) async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    if (_isSendingComment) return;
    setState(() => _isSendingComment = true);
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to comment on this story.',
    );
    if (!mounted) return;
    if (!allowed) {
      if (mounted) setState(() => _isSendingComment = false);
      return;
    }
    final session = ref.read(authSessionProvider).value;
    if (session == null) {
      if (mounted) setState(() => _isSendingComment = false);
      return;
    }
    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        final comment = WallComment(
          id: const Uuid().v4(),
          authorId: session.userId,
          text: text,
          createdAt: DateTime.now(),
        );
        await repo.addWallComment(tripId, comment);
        _commentController.clear();
      },
      errorMessage: 'Unable to send comment.',
    );
    if (!mounted) return;
    if (!success && _commentController.text.isEmpty) {
      _commentController.text = text;
    }
    setState(() => _isSendingComment = false);
  }
}

class _StoryPayload {
  final String storyId;
  final TripStory story;
  final List<Member> members;
  final String destination;
  final String? heroImageUrl;
  final int? coverGradientId;

  const _StoryPayload({
    required this.storyId,
    required this.story,
    required this.members,
    required this.destination,
    required this.heroImageUrl,
    required this.coverGradientId,
  });
}

class _StoryDetailBody extends StatelessWidget {
  final TripStory story;
  final List<Member> members;
  final String destination;
  final String? heroImageUrl;
  final int? coverGradientId;
  final TextEditingController commentController;
  final VoidCallback? onLike;
  final VoidCallback? onSendComment;
  final bool isLiked;
  final int likeCount;

  const _StoryDetailBody({
    required this.story,
    required this.members,
    required this.destination,
    required this.heroImageUrl,
    required this.coverGradientId,
    required this.commentController,
    required this.onLike,
    required this.onSendComment,
    required this.isLiked,
    required this.likeCount,
  });

  @override
  Widget build(BuildContext context) {
    final stats = story.wallStats;
    final moments = story.moments.where((m) => m.isPublic).toList();

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: _gradientForTrip(
              destination: destination,
              coverGradientId: coverGradientId,
            ),
            image: heroImageUrl != null
                ? DecorationImage(
                    image: CachedNetworkImageProvider(heroImageUrl!),
                    fit: BoxFit.cover,
                  )
                : null,
          ),
        ),
        const SizedBox(height: 16),
        Text(
          story.headline.isNotEmpty
              ? story.headline
              : '$destination passport',
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Text(
          story.highlights.isNotEmpty
              ? story.highlights.join(' · ')
              : 'No highlights yet.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Icon(Icons.favorite_border, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text('$likeCount'),
            const SizedBox(width: 16),
            Icon(Icons.chat_bubble_outline, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text('${stats.comments}'),
            const Spacer(),
            TextButton.icon(
              onPressed: onLike,
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                size: 16,
                color: isLiked ? const Color(0xFFDC2626) : null,
              ),
              label: Text(isLiked ? 'Unlike' : 'Like'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Moments',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (moments.isEmpty)
          const _InlineEmptyState(
            title: 'No moments yet',
            subtitle: 'Trip moments will show up here.',
            icon: Icons.auto_awesome_outlined,
          )
        else
          ...moments.map(
            (moment) => _MomentCard(moment: moment, members: members),
          ),
        const SizedBox(height: 16),
        Text(
          'Photos',
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        if (story.photos.isEmpty)
          const _InlineEmptyState(
            title: 'No photos yet',
            subtitle: 'Add photos to bring the story to life.',
            icon: Icons.photo_outlined,
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: story.photos
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
        if (story.wallComments.isEmpty)
          const _InlineEmptyState(
            title: 'No comments yet',
            subtitle: 'Be the first to react to this story.',
            icon: Icons.chat_bubble_outline,
          )
        else
          ...story.wallComments.map(
            (comment) => _CommentCard(comment: comment, members: members),
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
              onPressed: onSendComment,
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

class _MomentCard extends StatelessWidget {
  final StoryMoment moment;
  final List<Member> members;

  const _MomentCard({required this.moment, required this.members});

  @override
  Widget build(BuildContext context) {
    final author = members.firstWhere(
      (m) => m.userId == moment.authorId,
      orElse: () => members.first,
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
          _Avatar(initials: _initials(author.name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.name,
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
              ],
            ),
          ),
          Text(
            _timeAgo(moment.createdAt),
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
      borderRadius: BorderRadius.circular(16),
      child: Image(
        image: CachedNetworkImageProvider(photo.url),
        width: 100,
        height: 100,
        fit: BoxFit.cover,
      ),
    );
  }
}

class _CommentCard extends StatelessWidget {
  final WallComment comment;
  final List<Member> members;

  const _CommentCard({required this.comment, required this.members});

  @override
  Widget build(BuildContext context) {
    final author = members.firstWhere(
      (m) => m.userId == comment.authorId,
      orElse: () => members.first,
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
          _Avatar(initials: _initials(author.name)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  author.name,
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
        children: [
          Container(
            height: 42,
            width: 42,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: const Color(0xFF4F46E5)),
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
                const SizedBox(height: 4),
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

class _StoryDetailLoading extends StatelessWidget {
  const _StoryDetailLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _LoadingBox(height: 200),
        const SizedBox(height: 16),
        _LoadingBox(height: 22, width: 220),
        const SizedBox(height: 12),
        _LoadingBox(height: 14, width: 180),
        const SizedBox(height: 24),
        _LoadingBox(height: 120),
        const SizedBox(height: 12),
        _LoadingBox(height: 120),
      ],
    );
  }
}

class _LoadingBox extends StatelessWidget {
  final double height;
  final double? width;

  const _LoadingBox({required this.height, this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: const Color(0xFFE2E8F0),
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  final String initials;

  const _Avatar({required this.initials});

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 18,
      backgroundColor: const Color(0xFFE2E8F0),
      child: Text(
        initials,
        style: Theme.of(
          context,
        ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

String _initials(String name) {
  final parts = name.trim().split(' ');
  if (parts.isEmpty) return 'TP';
  if (parts.length == 1) return parts.first[0].toUpperCase();
  return (parts.first[0] + parts.last[0]).toUpperCase();
}

String _timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}

LinearGradient _gradientForTrip({
  required String destination,
  required int? coverGradientId,
}) {
  final gradients = [
    const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF6366F1)]),
    const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF14B8A6)]),
    const LinearGradient(colors: [Color(0xFFF97316), Color(0xFFEF4444)]),
    const LinearGradient(colors: [Color(0xFFA855F7), Color(0xFFEC4899)]),
    const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFF84CC16)]),
  ];
  final index = coverGradientId != null
      ? coverGradientId.clamp(0, gradients.length - 1)
      : destination.hashCode.abs() % gradients.length;
  return gradients[index];
}
