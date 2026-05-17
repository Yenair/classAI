import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';

/// A [MaterialBanner] that displays when there are unresolved sync conflicts.
///
/// Reads [unresolvedConflictsProvider] and shows a warning banner with a
/// "REVIEW" button that navigates to `/conflicts`.
class ConflictBanner extends ConsumerWidget {
  const ConflictBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictCount = ref.watch(unresolvedConflictsProvider);
    final theme = Theme.of(context);

    if (conflictCount <= 0) {
      return const SizedBox.shrink();
    }

    return MaterialBanner(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      leading: Icon(
        Icons.warning_amber_rounded,
        color: theme.colorScheme.error,
      ),
      content: Text(
        conflictCount == 1
            ? '1 unresolved conflict'
            : '$conflictCount unresolved conflicts',
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w500,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => context.push('/conflicts'),
          child: const Text('REVIEW'),
        ),
      ],
    );
  }
}
