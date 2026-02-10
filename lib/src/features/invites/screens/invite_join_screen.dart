import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/providers.dart';
import 'package:flutter_application_trial/src/utils/async_guard.dart';
import 'package:flutter_application_trial/src/utils/invite_utils.dart';
import 'package:flutter_application_trial/src/features/trips/screens/trip_detail_screen.dart';
import 'package:flutter_application_trial/src/widgets/app_scaffold.dart';
import 'package:flutter_application_trial/src/widgets/primary_button.dart';

enum _InviteJoinStatus {
  ready,
  invalid,
  expired,
  used,
  tripDeleted,
  network,
}

final _inviteJoinProvider = FutureProvider.family<_InviteJoinData, String>(
  (ref, token) async {
    final repo = ref.read(repositoryProvider);
    try {
      final invite = await repo.getInviteByToken(token);
      if (invite == null) {
        return const _InviteJoinData(status: _InviteJoinStatus.invalid);
      }
      if (invite.isUsed) {
        return _InviteJoinData(
          status: _InviteJoinStatus.used,
          invite: invite,
        );
      }
      if (DateTime.now().isAfter(invite.expiresAt)) {
        return _InviteJoinData(
          status: _InviteJoinStatus.expired,
          invite: invite,
        );
      }
      final trip = await repo.getTripById(invite.tripId);
      if (trip == null) {
        return _InviteJoinData(
          status: _InviteJoinStatus.tripDeleted,
          invite: invite,
        );
      }
      final session = ref.read(authSessionProvider).value;
      final isMember = session != null &&
          trip.members.any((member) => member.userId == session.userId);
      return _InviteJoinData(
        status: _InviteJoinStatus.ready,
        invite: invite,
        trip: trip,
        hostName: _hostNameForTrip(trip),
        isMember: isMember,
      );
    } catch (_) {
      return const _InviteJoinData(status: _InviteJoinStatus.network);
    }
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
  bool _showManualEntry = false;
  late final TextEditingController _inputController;
  String? _token;
  String? _inputError;

  @override
  void initState() {
    super.initState();
    _inputController = TextEditingController(text: widget.inviteInput);
    _token = parseInviteTokenFromText(widget.inviteInput);
    _showManualEntry = _token == null;
    if (_token == null) {
      _inputError = 'Paste a valid invite link or token.';
    }
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Join Trip',
      onHome: () => Navigator.of(context).popUntil((route) => route.isFirst),
      padding: EdgeInsets.zero,
      body: _showManualEntry
          ? _InviteInputState(
              controller: _inputController,
              errorText: _inputError,
              onContinue: _handleTokenInput,
              onCancel: _token == null ? _goHome : _showPreview,
            )
          : _buildPreview(context),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final token = _token;
    if (token == null) {
      return _InviteProblemState(
        title: 'Invite link missing',
        message: 'Paste the invite link or ask the host for a new one.',
        primaryLabel: 'Enter invite code',
        onPrimary: _openManualEntry,
        secondaryLabel: 'Go home',
        onSecondary: _goHome,
      );
    }

    final inviteAsync = ref.watch(_inviteJoinProvider(token));
    return inviteAsync.when(
      data: (data) => _buildInviteState(context, data),
      loading: () => const _InviteJoinLoading(),
      error: (e, st) => _InviteProblemState(
        title: 'Unable to load invite',
        message: 'Check your connection and try again.',
        primaryLabel: 'Retry',
        onPrimary: () => ref.refresh(_inviteJoinProvider(token)),
        secondaryLabel: 'Trouble joining?',
        onSecondary: _openManualEntry,
      ),
    );
  }

  Widget _buildInviteState(BuildContext context, _InviteJoinData data) {
    if (data.status == _InviteJoinStatus.ready &&
        data.invite != null &&
        data.trip != null) {
      if (data.isMember) {
        return _AlreadyMemberState(
          onOpen: () => _openTrip(data.trip!.id),
          onClose: _goHome,
        );
      }
      return _InvitePreview(
        trip: data.trip!,
        invite: data.invite!,
        hostName: data.hostName ?? 'Trip host',
        onJoin: _joining ? null : () => _handleJoin(data),
        onDecline: _declineInvite,
        onSaveForLater: _saveForLater,
        onTrouble: _openManualEntry,
        joining: _joining,
      );
    }

    final isNetwork = data.status == _InviteJoinStatus.network;
    return _InviteProblemState(
      title: _statusTitle(data.status),
      message: _statusMessage(data.status),
      primaryLabel: isNetwork ? 'Retry' : 'Trouble joining?',
      onPrimary: isNetwork
          ? () => ref.refresh(_inviteJoinProvider(_token!))
          : _openManualEntry,
      secondaryLabel: isNetwork ? 'Trouble joining?' : 'Go home',
      onSecondary: isNetwork ? _openManualEntry : _goHome,
    );
  }

  void _handleTokenInput() {
    final token = parseInviteTokenFromText(_inputController.text);
    setState(() {
      _token = token;
      _inputError = token == null ? 'Paste a valid invite link or token.' : null;
      if (token != null) {
        _showManualEntry = false;
      }
    });
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
          data.trip!.id,
          Member(
            userId: session.userId,
            name: displayName,
            email: session.email,
            avatarUrl: photoUrl,
            role: data.invite!.role,
            joinedAt: DateTime.now(),
          ),
        );
        await repo.markInviteAsUsed(data.invite!.id);
        ref.invalidate(tripByIdProvider(data.trip!.id));
        ref.invalidate(userTripsProvider);
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => TripDetailScreen(tripId: data.trip!.id),
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

  Future<void> _saveForLater() async {
    final token = _token;
    if (token == null) return;
    await InviteTokenStore.savePendingToken(token);
    if (!mounted) return;
    showGuardedSnackBar(context, 'Invite saved for later.');
    _goHome();
  }

  Future<void> _declineInvite() async {
    await InviteTokenStore.clearPendingToken();
    if (!mounted) return;
    showGuardedSnackBar(context, 'Invite declined.');
    _goHome();
  }

  void _openManualEntry() {
    setState(() => _showManualEntry = true);
  }

  void _showPreview() {
    setState(() => _showManualEntry = false);
  }

  void _goHome() {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  void _openTrip(String tripId) {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => TripDetailScreen(tripId: tripId),
      ),
    );
  }
}

class _InvitePreview extends StatelessWidget {
  final Trip trip;
  final Invite invite;
  final String hostName;
  final VoidCallback? onJoin;
  final VoidCallback onDecline;
  final VoidCallback onSaveForLater;
  final VoidCallback onTrouble;
  final bool joining;

  const _InvitePreview({
    required this.trip,
    required this.invite,
    required this.hostName,
    required this.onJoin,
    required this.onDecline,
    required this.onSaveForLater,
    required this.onTrouble,
    required this.joining,
  });

  @override
  Widget build(BuildContext context) {
    final roleLabel = _roleLabel(invite.role);
    final dates = _formatDateRange(trip.startDate, trip.endDate);
    final members = trip.members;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          'Join ${trip.destination}',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          dates,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
        const SizedBox(height: 16),
        _InfoRow(
          icon: Icons.person_outline,
          title: 'Host',
          value: hostName,
        ),
        const SizedBox(height: 10),
        _InfoRow(
          icon: Icons.verified_user_outlined,
          title: 'Role',
          value: roleLabel,
        ),
        const SizedBox(height: 10),
        _InfoRow(
          icon: Icons.people_alt_outlined,
          title: 'Members',
          value: '${members.length} travelers',
        ),
        const SizedBox(height: 12),
        _MemberPreview(members: members),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Text(
            'You will join as a $roleLabel. You can view the trip plan and '
            'collaborate based on this role.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF475569)),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: PrimaryButton(
            label: 'Join trip',
            onPressed: onJoin,
            isLoading: joining,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onSaveForLater,
                child: const Text('Save for later'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextButton(
                onPressed: onDecline,
                child: const Text('Decline'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton(
            onPressed: onTrouble,
            child: const Text('Trouble joining?'),
          ),
        ),
      ],
    );
  }
}

class _AlreadyMemberState extends StatelessWidget {
  final VoidCallback onOpen;
  final VoidCallback onClose;

  const _AlreadyMemberState({
    required this.onOpen,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle_outline, size: 48),
            const SizedBox(height: 12),
            Text(
              'You are already a member of this trip.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onOpen,
                child: const Text('Open trip'),
              ),
            ),
            TextButton(
              onPressed: onClose,
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InviteInputState extends StatelessWidget {
  final TextEditingController controller;
  final String? errorText;
  final VoidCallback onContinue;
  final VoidCallback? onCancel;

  const _InviteInputState({
    required this.controller,
    required this.errorText,
    required this.onContinue,
    this.onCancel,
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
              'Enter an invite code',
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
            if (onCancel != null) ...[
              const SizedBox(height: 8),
              TextButton(
                onPressed: onCancel,
                child: const Text('Back to invite'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InviteProblemState extends StatelessWidget {
  final String title;
  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String secondaryLabel;
  final VoidCallback onSecondary;

  const _InviteProblemState({
    required this.title,
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
    required this.secondaryLabel,
    required this.onSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 48, color: Colors.red[400]),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onPrimary,
                child: Text(primaryLabel),
              ),
            ),
            TextButton(
              onPressed: onSecondary,
              child: Text(secondaryLabel),
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

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF475569)),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _MemberPreview extends StatelessWidget {
  final List<Member> members;

  const _MemberPreview({required this.members});

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Text(
        'No members yet',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    final visible = members.take(5).toList();
    return Row(
      children: [
        ...visible.map(
          (member) => Padding(
            padding: const EdgeInsets.only(right: 6),
            child: CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFFE2E8F0),
              child: Text(
                _initials(member.name),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        if (members.length > visible.length)
          Text(
            '+${members.length - visible.length} more',
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
    );
  }
}

class _InviteJoinData {
  final Invite? invite;
  final Trip? trip;
  final _InviteJoinStatus status;
  final String? hostName;
  final bool isMember;

  const _InviteJoinData({
    this.invite,
    this.trip,
    required this.status,
    this.hostName,
    this.isMember = false,
  });
}

String _hostNameForTrip(Trip trip) {
  try {
    final owner = trip.members.firstWhere(
      (member) => member.userId == trip.ownerId,
    );
    return owner.name;
  } catch (_) {}
  try {
    final owner = trip.members.firstWhere(
      (member) => member.role == MemberRole.owner,
    );
    return owner.name;
  } catch (_) {}
  return trip.members.isNotEmpty ? trip.members.first.name : 'Trip host';
}

String _formatDateRange(DateTime start, DateTime end) {
  final startFormat = DateFormat('MMM d');
  final endFormat = DateFormat('MMM d, yyyy');
  if (start.year == end.year) {
    return '${startFormat.format(start)} - ${endFormat.format(end)}';
  }
  final fullFormat = DateFormat('MMM d, yyyy');
  return '${fullFormat.format(start)} - ${fullFormat.format(end)}';
}

String _roleLabel(MemberRole role) {
  switch (role) {
    case MemberRole.viewer:
      return 'Viewer';
    case MemberRole.collaborator:
      return 'Editor';
    case MemberRole.owner:
      return 'Owner';
  }
}

String _statusTitle(_InviteJoinStatus status) {
  switch (status) {
    case _InviteJoinStatus.invalid:
      return 'Invite not found';
    case _InviteJoinStatus.expired:
      return 'Invite expired';
    case _InviteJoinStatus.used:
      return 'Invite already used';
    case _InviteJoinStatus.tripDeleted:
      return 'Trip no longer exists';
    case _InviteJoinStatus.network:
      return 'Network issue';
    case _InviteJoinStatus.ready:
      return 'Invite ready';
  }
}

String _statusMessage(_InviteJoinStatus status) {
  switch (status) {
    case _InviteJoinStatus.invalid:
      return 'Ask the host for a new invite link.';
    case _InviteJoinStatus.expired:
      return 'This invite expired. Request a fresh link.';
    case _InviteJoinStatus.used:
      return 'This invite was already used. Ask for a new one.';
    case _InviteJoinStatus.tripDeleted:
      return 'The host removed this trip.';
    case _InviteJoinStatus.network:
      return 'We could not load this invite. Check your connection.';
    case _InviteJoinStatus.ready:
      return 'Invite ready.';
  }
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'));
  if (parts.isEmpty) return '';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts.first.substring(0, 1) + parts.last.substring(0, 1))
      .toUpperCase();
}
