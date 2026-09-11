import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';

/// Sync indicator for the AppBar.
///
/// Renders a pill-shaped container icon whose fill colour reflects the
/// current [SyncStatus].  Stitch pattern: subtle surface container with
/// a soft tinted fill; tint matches the status colour at low opacity.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncData = ref.watch(syncStatusProvider);
    final cs = Theme.of(context).colorScheme;

    final label = statusLabel(syncData.status);
    final (IconData icon, Color tint) = switch (syncData.status) {
      SyncStatus.offline => (Icons.cloud_off, cs.onSurfaceVariant),
      SyncStatus.syncing => (Icons.cloud_sync, cs.primary),
      SyncStatus.synced => (Icons.cloud_done, cs.primary),
      SyncStatus.error => (Icons.cloud_off, cs.error),
    };

    return IconButton(
      tooltip: label,
      onPressed: () async {
        final notifier = ref.read(syncStatusProvider.notifier);
        if (syncData.status == SyncStatus.syncing) {
          _showSyncDetailsSheet(
            context,
            ref,
            syncData,
          );
          return;
        }
        await notifier.syncNow();
        if (!context.mounted) return;
        _showSyncDetailsSheet(
          context,
          ref,
          ref.read(syncStatusProvider),
        );
      },
      icon: RepaintBoundary(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeInOut,
          switchOutCurve: Curves.easeInOut,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: animation,
                child: child,
              ),
            );
          },
          child: Container(
            key: ValueKey(syncData.status),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: tint,
            ),
          ),
        ),
      ),
    );
  }

  void _showSyncDetailsSheet(
    BuildContext context,
    WidgetRef ref,
    SyncStatusData data,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _SyncDetailsSheet(data: data, ref: ref),
    );
  }
}

class _SyncDetailsSheet extends ConsumerWidget {
  const _SyncDetailsSheet({required this.data, required this.ref});

  final SyncStatusData data;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final dateFormat = DateFormat('MMM d, yyyy – h:mm a');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sheet handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Title row
            Row(
              children: [
                Icon(Icons.history_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 10),
                Text(
                  'Sync Details',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Stat rows
            _StatRow(label: 'Status', value: statusLabel(data.status), cs: cs),
            const SizedBox(height: 12),
            _StatRow(
                label: 'Network',
                value: data.isOnline ? 'Connected' : 'Offline',
                cs: cs),
            const SizedBox(height: 12),
            _StatRow(
              label: 'Last sync',
              value: data.lastSyncTime != null
                  ? dateFormat.format(data.lastSyncTime!)
                  : 'Never',
              cs: cs,
            ),
            const SizedBox(height: 12),
            _StatRow(
                label: 'Pending push',
                value: '${data.pendingPushCount} item(s)',
                cs: cs),
            const SizedBox(height: 12),
            _StatRow(
                label: 'Pending pull',
                value: '${data.pendingPullCount} item(s)',
                cs: cs),
            const SizedBox(height: 12),
            _StatRow(
                label: 'Conflicts', value: '${data.conflictCount}', cs: cs),

            const SizedBox(height: 28),
            // Sync Now
            SizedBox(
              width: double.infinity,
              height: 52,
              child: FilledButton(
                onPressed: data.isOnline && data.status != SyncStatus.syncing
                    ? () {
                        ref
                            .read(syncStatusProvider.notifier)
                            .syncNow();
                        Navigator.of(context).pop();
                      }
                    : null,
                child: const Text(
                  'Sync Now',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, required this.cs});
  final String label;
  final String value;
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface.withValues(alpha: 0.65),
                  fontWeight: FontWeight.w400,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  overflow: TextOverflow.ellipsis,
                ),
          ),
        ),
      ],
    );
  }
}

String statusLabel(SyncStatus s) => switch (s) {
      SyncStatus.offline => 'Offline',
      SyncStatus.syncing => 'Syncing…',
      SyncStatus.synced => 'Synced',
      SyncStatus.error => 'Tap to sync',
    };
