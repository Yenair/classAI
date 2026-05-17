import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Possible sync statuses for UI display.
enum SyncStatus {
  offline,
  syncing,
  synced,
  error,
}

/// Data exposed to the sync indicator widget.
class SyncStatusData {
  final SyncStatus status;
  final DateTime? lastSyncTime;
  final int pendingPushCount;
  final int pendingPullCount;
  final int conflictCount;
  final bool isOnline;

  const SyncStatusData({
    required this.status,
    this.lastSyncTime,
    this.pendingPushCount = 0,
    this.pendingPullCount = 0,
    this.conflictCount = 0,
    this.isOnline = false,
  });
}

/// Notifier that provides current sync status for UI display.
///
/// Reads from the [SyncService] state and the database to build
/// a [SyncStatusData] snapshot.
class SyncStatusNotifier extends Notifier<SyncStatusData> {
  @override
  SyncStatusData build() {
    return const SyncStatusData(status: SyncStatus.offline);
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Refresh sync status from the database and service.
  Future<void> refresh() async {
    try {
      final config = await _db.securityConfigDao.get();
      final pendingQueue = await _db.syncQueueDao.pendingEntries();
      final conflicts = await (_db.select(_db.conflicts)
            ..where((t) => t.resolution.equals('unresolved')))
          .get();

      final syncStatus = _determineSyncStatus(config);
      state = SyncStatusData(
        status: syncStatus,
        lastSyncTime: config.lastSyncAttemptTime,
        pendingPushCount: pendingQueue.length,
        pendingPullCount: 0, // Pull count tracked server-side
        conflictCount: conflicts.length,
        isOnline: true, // Simplified; real connectivity check later
      );
    } catch (_) {
      state = const SyncStatusData(status: SyncStatus.offline);
    }
  }

  SyncStatus _determineSyncStatus(SecurityConfigData config) {
    final lastSync = config.lastSyncAttemptTime;
    if (lastSync == null) return SyncStatus.offline;
    final diff = DateTime.now().difference(lastSync);
    if (diff.inMinutes > 15) return SyncStatus.error;
    return SyncStatus.synced;
  }
}

final syncStatusProvider =
    NotifierProvider<SyncStatusNotifier, SyncStatusData>(
  SyncStatusNotifier.new,
);
