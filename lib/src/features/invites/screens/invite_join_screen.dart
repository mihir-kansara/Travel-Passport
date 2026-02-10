import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/utils/invite_utils.dart';
import 'package:flutter_application_trial/src/features/trips/screens/trip_detail_screen.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/widgets/primary_button.dart';

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
  final String inviteInput;

  const InviteJoinScreen({super.key, required this.inviteInput});

  @override
  ConsumerState<InviteJoinScreen> createState() => _InviteJoinScreenState();
}

class _InviteJoinScreenState extends ConsumerState<InviteJoinScreen> {
  bool _joining = false;
  bool _handledMemberRedirect = false;
  late final TextEditingController _inputController;
  String? _token;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: widget.inviteInput);
    _token = parseInviteTokenFromText(widget.inviteInput);
    if (_token == null) {
      _inputError = 'Paste a valid invite token or link.';
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_token == null) {
      return AppScaffold(
        title: 'Join Trip',
        onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
        padding: EdgeInsets.zero,
        body: _InviteInputState(
          controller: _inputController,
          errorText: _inputError,
          onContinue: _handleTokenInput,
        ),
      );
    }
    final inviteAsync = ref.watch(_inviteJoinProvider(_token!));
    return AppScaffold(
      title: 'Join Trip',
      onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      padding: EdgeInsets.zero,
      body: inviteAsync.when(
        data: (data) {
          final session = ref.watch(authSessionProvider).value;
          if (session != null &&
              data.trip.members
                  .any((member) => member.userId == session.userId)) {
            if (!_handledMemberRedirect) {
              _handledMemberRedirect = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(
                    builder: (_) => TripDetailScreen(tripId: data.trip.id),
                  ),
                );
                showGuardedSnackBar(
                  context,
                  'You are already a member of this trip.',
                );
              });
            }
            return const _InviteJoinLoading();
          }
          return _InviteContent(
            trip: data.trip,
            onJoin: _joining ? null : () => _handleJoin(data),
            joining: _joining,
          );
        },
        loading: () => const _InviteJoinLoading(),
        error: (e, st) => _ErrorState(
          message: _errorMessage(e),
          onRetry: () => ref.refresh(_inviteJoinProvider(_token!)),
        ),
      ),
    );
  }

  void _handleTokenInput() {
    final token = parseInviteTokenFromText(_inputController.text);
    setState(() {
      _token = token;
      _inputError = token == null ? 'Paste a valid invite token or link.' : null;
    });
  }

  String _errorMessage(Object error) {
    if (error is Exception) {
      return error.toString().replaceFirst('Exception: ', '');
    }
    return 'Unable to load invite.';
  }

  Future<void> _handleJoin(_InviteJoinData data) async {
    if (_joining) return;
    setState(() => _joining = true);
    final token = _token;
    if (token == null) {
      if (mounted) setState(() => _joining = false);
      return;
    }
    final allowed = await ensureSignedIn(
      context,
      ref,
      message: 'Sign in to join this trip.',
      pendingInviteToken: token,
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
    final profile = await ref.read(currentUserProfileProvider.future);
    if (!mounted) return;
    final displayName = profile?.displayName.isNotEmpty == true
        ? profile!.displayName
        : session.displayName;
    final photoUrl = profile?.photoUrl ?? session.avatarUrl;
    final success = await runGuarded(
      context,
      () async {
        final repo = ref.read(repositoryProvider);
        await repo.addMember(
          data.trip.id,
          Member(
            userId: session.userId,
            name: displayName,
            email: session.email,
            avatarUrl: photoUrl,
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
            child: PrimaryButton(
              label: 'Join trip',
              onPressed: onJoin,
              isLoading: joining,
            ),
          ),
        ],
      ),
    );
  }
}

class _InviteInputState extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onContinue;

  const _InviteInputState({
    required this.controller,
    required this.errorText,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.link, size: 44),
            const SizedBox(height: 12),
            Text(
              'Paste an invite token or link',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'Example: https://travelpassport.app/invite/...',
                errorText: errorText,
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onContinue(),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PrimaryButton(
                label: 'Continue',
                onPressed: onContinue,
              ),
            ),
          ],
        ),
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
