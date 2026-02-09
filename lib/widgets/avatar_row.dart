import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/models/trip.dart';
import 'package:flutter_application_trial/ui/app_colors.dart';

class AvatarRow extends StatelessWidget {
  final List<Member> members;
  final double size;
  final int maxVisible;

  const AvatarRow({
    super.key,
    required this.members,
    this.size = 28,
    this.maxVisible = 4,
  });

  @override
  Widget build(BuildContext context) {
    final show = members.take(maxVisible).toList();
    final remaining = members.length - show.length;
    return Row(
      children: [
        for (final member in show)
          Container(
            margin: const EdgeInsets.only(right: 4),
            height: size,
            width: size,
            decoration: BoxDecoration(
              color: AppColors.border,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(member.name),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (remaining > 0)
          Container(
            height: size,
            width: size,
            decoration: BoxDecoration(
              color: AppColors.placeholderAlt,
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.surface, width: 2),
            ),
            alignment: Alignment.center,
            child: Text(
              '+$remaining',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
      ],
    );
  }
}

String _initials(String name) {
  final parts = name.split(' ').where((p) => p.trim().isNotEmpty).toList();
  if (parts.isEmpty) return 'U';
  if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
  return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
}
