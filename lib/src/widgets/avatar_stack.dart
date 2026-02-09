import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/app_theme.dart';

class AvatarStack extends StatelessWidget {
  final List<String> initials;
  final double radius;

  const AvatarStack({super.key, required this.initials, this.radius = 16});

  @override
  Widget build(BuildContext context) {
    final visible = initials.take(4).toList();
    return SizedBox(
      height: radius * 2,
      child: Stack(
        children: [
          for (var i = 0; i < visible.length; i++)
            Positioned(
              left: i * (radius * 1.2),
              child: CircleAvatar(
                radius: radius,
                backgroundColor: AppColors.border,
                child: Text(
                  visible[i],
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
