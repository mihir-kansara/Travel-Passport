import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_application_trial/src/providers.dart';

void showGuardedSnackBar(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> runGuarded(
  BuildContext context,
  Future<void> Function() action, {
  String? successMessage,
  String? errorMessage,
  void Function(Object error)? onError,
}) async {
  try {
    await action();
    if (context.mounted && successMessage != null) {
      showGuardedSnackBar(context, successMessage);
    }
    return true;
  } catch (error) {
    if (onError != null) {
      onError(error);
    }
    if (context.mounted && errorMessage != null) {
      showGuardedSnackBar(context, errorMessage);
    }
    return false;
  }
}

Future<T?> runGuardedAsync<T>({
  required BuildContext context,
  required WidgetRef ref,
  required Future<T> Function() task,
  required ValueSetter<bool> setBusy,
  String? successMessage,
  String? errorMessage,
  void Function(Object error)? onError,
}) async {
  setBusy(true);
  try {
    final result = await task();
    if (!context.mounted) return result;
    if (successMessage != null) {
      showGuardedSnackBar(context, successMessage);
    }
    return result;
  } catch (error) {
    if (!context.mounted) return null;
    if (onError != null) {
      onError(error);
    }
    if (errorMessage != null) {
      showGuardedSnackBar(context, errorMessage);
    }
    return null;
  } finally {
    if (context.mounted) {
      setBusy(false);
    }
  }
}

Future<bool> ensureSignedIn(
  BuildContext context,
  WidgetRef ref, {
  String? message,
  String? pendingInviteToken,
}) async {
  final session = ref.read(authSessionProvider).value;
  if (session != null) return true;
  if (pendingInviteToken != null) {
    ref.read(pendingInviteTokenProvider.notifier).state = pendingInviteToken;
  }
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Sign in required'),
      content: Text(message ?? 'Sign in to continue.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Not now'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Sign in'),
        ),
      ],
    ),
  );
  if (result == true && context.mounted) {
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
  return false;
}
