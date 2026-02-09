import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/screens/trip_detail_screen.dart';

final _inviteJoinProvider = FutureProvider.family<_InviteJoinData, String>(
  (ref, token) async {
    final repo = ref.read(repositoryProvider);
    final invite = await repo.getInviteByToken(token);
    if (invite == null || !invite.isValid) {
      throw Exception('Invite link is invalid or expired.');
    }
    final trip = await repo.getTripById(invite.tripId);
    if (trip == null) {
      throw Exception('Trip no longer exists.');
    }
    return _InviteJoinData(invite: invite, trip: trip);
  },
);

class InviteJoinScreen extends ConsumerStatefulWidget {
  final String token;

  const InviteJoinScreen({super.key, required this.token});

  @override
  ConsumerState<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends ConsumerState<InviteJoinScreen> {
  bool _joining = false;

  @override
  Widget build(BuildContext context) {
    final inviteAsync = ref.watch(_inviteJoinProvider(widget.token));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Trip'),
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            onPressed: () =>
                Navigator.of(context).popUntil((route) => route.isFirst),
          ),
        ],
      ),
      body: inviteAsync.when(
        data: (data) => _InviteContent(
          trip: data.trip,
          onJoin: _joining ? null : () => _handleJoin(data),
          joining: _joining,
        ),
        loading: () => const _InviteJoinLoading(),
        error: (e, st) => _ErrorState(
          message: 'Unable to load invite.',
          onRetry: () => ref.refresh(_inviteJoinProvider(widget.token)),
        ),
      ),
    );
  }

  Future<void> _handleJoin(_InviteJoinData data) async {
    if (_joining) return;
    setState(() => _joining = true);
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to join this trip.',
      pendingInviteToken: widget.token,
    );
    if (!mounted) return;
    if (!allowed) {
      if (mounted) setState(() => _joining = false);
      return;
    }
    final session = ref.read(authSessionProvider).value;
    if (session == null) {
      if (mounted) setState(() => _joining = false);
      return;
    }
    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.addMember(
          data.trip.id,
          Member(
            userId: session.userId,
            name: session.displayName,
            email: session.email,
            avatarUrl: session.avatarUrl,
            role: MemberRole.collaborator,
            joinedAt: DateTime.now(),
          ),
        );
        await repo.markInviteAsUsed(data.invite.id);
        ref.invalidate(tripByIdProvider(data.trip.id));
        ref.invalidate(userTripsProvider);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TripDetailScreen(tripId: data.trip.id),
          ),
        );
        showGuardedSnackBar(context, 'You joined the trip.');
      },
      errorMessage: 'Unable to join the trip.',
    );
    if (mounted) {
      setState(() => _joining = false);
    }
    if (!success) return;
  }
}

class _InviteContent extends StatelessWidget {
  final Trip trip;
  final VoidCallback? onJoin;
  final bool joining;

  const _InviteContent({
    required this.trip,
    required this.onJoin,
    required this.joining,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            trip.destination,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            trip.description,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Icon(Icons.people_alt_outlined, size: 18),
              const SizedBox(width: 6),
              Text('${trip.members.length} travelers'),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onJoin,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F46E5),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: joining
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Join trip'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.red[400]),
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

class _InviteJoinLoading extends StatelessWidget {
  const _InviteJoinLoading();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: const [
        _LoadingBox(height: 28, width: 220),
        SizedBox(height: 12),
        _LoadingBox(height: 18, width: 260),
        SizedBox(height: 24),
        _LoadingBox(height: 120),
        SizedBox(height: 24),
        _LoadingBox(height: 48),
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

class _InviteJoinData {
  final Invite invite;
  final Trip trip;

  const _InviteJoinData({required this.invite, required this.trip});
}
