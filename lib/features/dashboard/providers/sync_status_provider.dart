import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/features/auth/providers/auth_provider.dart'
    show securityServiceProvider;
import 'package:classai/main.dart' show databaseProvider, navigatorKey;

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

/// Provider that lazily constructs a [SyncService] instance.
///
/// Loads the school's server ID from the database to configure both the
/// [SyncService] and its [SupabaseSyncRemoteApi].
final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  final db = ref.watch(databaseProvider);
  final securityService = ref.watch(securityServiceProvider);

  final school = await db.schoolsDao.get();
  final schoolId = school?.serverId ?? '';

  return SyncService(
    db: db,
    schoolId: schoolId,
    securityService: securityService,
    remoteApi: SupabaseSyncRemoteApi(schoolId: schoolId),
  );
});

/// Notifier that provides current sync status for UI display.
///
/// Reads from the [SyncService] state and the database to build
/// a [SyncStatusData] snapshot. Monitors network connectivity via
/// [connectivity_plus] and updates [isOnline] accordingly.
///
/// Note: This checks network connectivity (link-layer), not actual
/// internet access (which would require a ping to a known host).
class SyncStatusNotifier extends Notifier<SyncStatusData> {
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  @override
  SyncStatusData build() {
    // Monitor connectivity changes in real time.
    final connectivity = Connectivity();
    _connectivitySubscription =
        connectivity.onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      // Preserve existing state values, only update isOnline.
      state = SyncStatusData(
        status: state.status,
        lastSyncTime: state.lastSyncTime,
        pendingPushCount: state.pendingPushCount,
        pendingPullCount: state.pendingPullCount,
        conflictCount: state.conflictCount,
        isOnline: isOnline,
      );
    });

    ref.onDispose(() {
      _connectivitySubscription?.cancel();
    });

    return const SyncStatusData(status: SyncStatus.offline);
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Trigger a full sync cycle (pull‑merge‑push) and update UI status.
  ///
  /// Sets the status to [SyncStatus.syncing], calls
  /// [SyncService.onConnectivityRestored()], then refreshes the display.
  /// On failure the status is set to [SyncStatus.error] and a snackbar is
  /// shown with the error message.
  Future<void> syncNow() async {
    final currentState = state;
    try {
      // Immediately show syncing state
      state = SyncStatusData(
        status: SyncStatus.syncing,
        lastSyncTime: currentState.lastSyncTime,
        pendingPushCount: currentState.pendingPushCount,
        pendingPullCount: currentState.pendingPullCount,
        conflictCount: currentState.conflictCount,
        isOnline: currentState.isOnline,
      );

      // Resolve SyncService (may load school info asynchronously)
      final syncService = await ref.read(syncServiceProvider.future);

      // Run the full sync cycle
      await syncService.onConnectivityRestored();
    } catch (e, _) {
      // Mark as error
      state = SyncStatusData(
        status: SyncStatus.error,
        lastSyncTime: currentState.lastSyncTime,
        pendingPushCount: currentState.pendingPushCount,
        pendingPullCount: currentState.pendingPullCount,
        conflictCount: currentState.conflictCount,
        isOnline: currentState.isOnline,
      );

      // Show snackbar with error details
      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        showErrorToast(context: context, message: 'Sync failed: $e');
      }
      return;
    }

    // Refresh display state after successful sync
    await refresh();
  }

  /// Refresh sync status from the database and service.
  Future<void> refresh() async {
    try {
      final config = await _db.securityConfigDao.get();
      final pendingQueue = await _db.syncQueueDao.pendingEntries();
      final conflicts = await (_db.select(_db.conflicts)
            ..where((t) => t.resolution.equals('unresolved')))
          .get();

      // Check current connectivity on refresh.
      final connectivity = Connectivity();
      final results = await connectivity.checkConnectivity();
      final isOnline = results.any((r) => r != ConnectivityResult.none);

      final syncStatus = _determineSyncStatus(config);
      state = SyncStatusData(
        status: syncStatus,
        lastSyncTime: config.lastSyncAttemptTime,
        pendingPushCount: pendingQueue.length,
        pendingPullCount: 0, // Pull count tracked server-side
        conflictCount: conflicts.length,
        isOnline: isOnline,
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

final syncStatusProvider = NotifierProvider<SyncStatusNotifier, SyncStatusData>(
  SyncStatusNotifier.new,
);

/// Computed provider that exposes just the offline state.
final isOfflineProvider = Provider<bool>((ref) {
  return !ref.watch(syncStatusProvider).isOnline;
});
