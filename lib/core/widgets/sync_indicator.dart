import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';

/// Sync indicator icon in the AppBar.
///
/// Renders an [IconButton] whose icon and colour reflect the current
/// [SyncStatus]. On tap, shows a modal bottom sheet with sync details.
class SyncIndicator extends ConsumerWidget {
  const SyncIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncData = ref.watch(syncStatusProvider);

    final (IconData icon, Color color, String tooltip) = switch (syncData.status) {
      SyncStatus.offline => (Icons.cloud_off, Colors.grey, 'Offline'),
      SyncStatus.syncing => (Icons.cloud_sync, Colors.blue, 'Syncing…'),
      SyncStatus.synced => (Icons.cloud_done, Colors.green, 'Synced'),
      SyncStatus.error => (Icons.cloud_off, Colors.red, 'Sync error'),
    };

    return IconButton(
      icon: Icon(icon, color: color),
      tooltip: tooltip,
      onPressed: () => _showSyncDetailsSheet(context, ref, syncData),
    );
  }

  void _showSyncDetailsSheet(BuildContext context, WidgetRef ref, SyncStatusData data) {
    showModalBottomSheet(
      context: context,
      builder: (_) => _SyncDetailsSheet(data: data, ref: ref),
    );
  }
}

class _SyncDetailsSheet extends ConsumerWidget {
  final SyncStatusData data;
  final WidgetRef ref;

  const _SyncDetailsSheet({required this.data, required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('MMM d, yyyy – h:mm a');

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sync Details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _infoRow(
            context,
            'Status',
            switch (data.status) {
              SyncStatus.offline => 'Offline',
              SyncStatus.syncing => 'Syncing…',
              SyncStatus.synced => 'Synced',
              SyncStatus.error => 'Error',
            },
          ),
          const SizedBox(height: 8),
          _infoRow(
            context,
            'Network',
            data.isOnline ? 'Connected' : 'Offline',
          ),
          const SizedBox(height: 8),
          _infoRow(
            context,
            'Last sync',
            data.lastSyncTime != null
                ? dateFormat.format(data.lastSyncTime!)
                : 'Never',
          ),
          const SizedBox(height: 8),
          _infoRow(
            context,
            'Pending push',
            '${data.pendingPushCount} item(s)',
          ),
          const SizedBox(height: 8),
          _infoRow(
            context,
            'Pending pull',
            '${data.pendingPullCount} item(s)',
          ),
          const SizedBox(height: 8),
          _infoRow(
            context,
            'Conflicts',
            '${data.conflictCount}',
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: data.isOnline && data.status != SyncStatus.syncing
                  ? () {
                      ref.read(syncStatusProvider.notifier).refresh();
                      Navigator.of(context).pop();
                    }
                  : null,
              child: const Text('Sync Now'),
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
