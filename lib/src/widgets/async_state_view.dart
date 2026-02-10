import 'package:flutter/material.dart';
import 'package:flutter_application_trial/src/widgets/empty_state_card.dart';
import 'package:flutter_application_trial/src/widgets/loading_placeholder.dart';

class AsyncLoadingView extends StatelessWidget {
  final int? itemCount;
  final double? itemHeight;
  final EdgeInsets? padding;
  final String? message;

  const AsyncLoadingView.list({
    super.key,
    this.itemCount = 3,
    this.itemHeight = 160,
    this.padding,
    this.message,
  });

  const AsyncLoadingView.centered({
    super.key,
    this.message,
  })  : itemCount = null,
        itemHeight = null,
        padding = null;

  bool get _isList => itemCount != null && itemHeight != null;

  @override
  Widget build(BuildContext context) {
    if (_isList) {
      return Column(
        children: [
          Expanded(
            child: LoadingPlaceholder(
              itemCount: itemCount ?? 3,
              itemHeight: itemHeight ?? 160,
              padding: padding ??
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            ),
          ),
          if (message != null) ...[
            const SizedBox(height: 8),
            Text(
              message!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
          ],
        ],
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          if (message != null) ...[
            const SizedBox(height: 12),
            Text(message!, style: Theme.of(context).textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}

class AsyncErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String retryLabel;

  const AsyncErrorView({
    super.key,
    required this.message,
    required this.onRetry,
    this.retryLabel = 'Retry',
  });

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
              label: Text(retryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

class AsyncEmptyView extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final IconData? actionIcon;
  final String? secondaryActionLabel;
  final VoidCallback? onSecondaryAction;

  const AsyncEmptyView({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.actionLabel,
    this.onAction,
    this.actionIcon,
    this.secondaryActionLabel,
    this.onSecondaryAction,
  });

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      actionLabel: actionLabel,
      onAction: onAction,
      actionIcon: actionIcon,
      secondaryActionLabel: secondaryActionLabel,
      onSecondaryAction: onSecondaryAction,
    );
  }
}
