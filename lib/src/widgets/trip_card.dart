import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/src/app_theme.dart';
import 'package:flutter_application_trial/src/widgets/avatar_stack.dart';

class TripCard extends StatelessWidget {
  final Trip trip;
  final VoidCallback? onTap;
  final VoidCallback? onPlanner;
  final VoidCallback? onStory;
  final VoidCallback? onInvite;
  final bool muted;
  final bool isDraft;

  const TripCard({
    super.key,
    required this.trip,
    this.onTap,
    this.onPlanner,
    this.onStory,
    this.onInvite,
    this.muted = false,
    this.isDraft = false,
  });

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d');
    final startStr = dateFormat.format(trip.startDate);
    final endStr = dateFormat.format(trip.endDate);
    final status = _statusLabel(trip, isDraft);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadii.md),
      child: Container(
        decoration: BoxDecoration(
          color: muted ? AppColors.placeholderAlt : AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadii.md),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 140,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(AppRadii.md),
                ),
                gradient: _gradientForTrip(trip),
                image: trip.heroImageUrl != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(trip.heroImageUrl!),
                        fit: BoxFit.cover,
                        colorFilter: muted
                            ? const ColorFilter.mode(
                                Colors.black12,
                                BlendMode.darken,
                              )
                            : null,
                      )
                    : null,
              ),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(AppRadii.md),
                  ),
                  color: Colors.black.withValues(alpha: 0.2),
                ),
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      trip.destination,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '$startStr - $endStr',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _StatusChip(label: status),
                      AvatarStack(initials: _memberInitials(trip)),
                    ],
                  ),
                  if (trip.description.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      trip.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.mutedText,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickActionButton(
                          label: 'Planner',
                          icon: Icons.event_note_outlined,
                          onPressed: onPlanner,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _QuickActionButton(
                          label: 'Story',
                          icon: Icons.auto_stories_outlined,
                          onPressed: onStory,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: _QuickActionButton(
                          label: 'Invite',
                          icon: Icons.person_add_alt_outlined,
                          onPressed: onInvite,
                        ),
                      ),
                    ],
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

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, semanticLabel: label),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          textStyle: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;

  const _StatusChip({required this.label});

  @override
  Widget build(BuildContext context) {
    final tone = _statusTone(label);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: tone.text,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

String _statusLabel(Trip trip, bool isDraft) {
  if (isDraft) return 'Draft';
  if (trip.story.isLive) return 'Live';
  if (trip.isPast) return 'Past';
  return 'Upcoming';
}

List<String> _memberInitials(Trip trip) {
  return trip.members
      .map((member) => member.name)
      .where((name) => name.trim().isNotEmpty)
      .map((name) {
        final parts = name.split(' ').where((p) => p.trim().isNotEmpty).toList();
        if (parts.isEmpty) return 'U';
        if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
        return (parts[0].substring(0, 1) + parts[1].substring(0, 1))
            .toUpperCase();
      })
      .toList();
}

_StatusTone _statusTone(String label) {
  switch (label) {
    case 'Live':
      return const _StatusTone(
        background: Color(0xFFDCFCE7),
        text: Color(0xFF166534),
      );
    case 'Past':
      return const _StatusTone(
        background: Color(0xFFF1F5F9),
        text: Color(0xFF475569),
      );
    case 'Draft':
      return const _StatusTone(
        background: Color(0xFFFFF7ED),
        text: Color(0xFFB45309),
      );
    default:
      return const _StatusTone(
        background: Color(0xFFE0E7FF),
        text: Color(0xFF3730A3),
      );
  }
}

class _StatusTone {
  final Color background;
  final Color text;

  const _StatusTone({required this.background, required this.text});
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
