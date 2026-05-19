import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';

/// A compact surface-card banner shown when there are unresolved sync conflicts.
///
/// Reads [unresolvedConflictsProvider] and shows a warning surface-card with a
/// "REVIEW" action that navigates to `/conflicts`.
///
/// Stitch pattern: `error-container` background, error-icon left accent, and
/// uppercase-bold REVIEW button.
class ConflictBanner extends ConsumerWidget {
  const ConflictBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conflictCount = ref.watch(unresolvedConflictsProvider);
    final cs = Theme.of(context).colorScheme;

    if (conflictCount <= 0) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 4),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: cs.onErrorContainer,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              conflictCount == 1
                  ? '1 unresolved conflict'
                  : '$conflictCount unresolved conflicts',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cs.onErrorContainer,
                    height: 1.3,
                  ),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/conflicts'),
            style: TextButton.styleFrom(
              foregroundColor: cs.onErrorContainer,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
            ),
            child: const Text('REVIEW'),
          ),
        ],
      ),
    );
  }
}
