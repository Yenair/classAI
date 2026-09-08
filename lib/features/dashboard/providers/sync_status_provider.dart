import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/utils/platform_helper.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:classai/core/widgets/app_toast.dart';
import 'package:classai/features/auth/providers/auth_provider.dart'
    show authProvider, authServiceProvider, securityServiceProvider;
import 'package:classai/features/dashboard/providers/credit_state_provider.dart'
    show dailyCreditStateProvider;
import 'package:classai/features/dashboard/providers/dashboard_data_providers.dart';
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
/// Loads the school's server ID from the auth provider (which holds the
/// authenticated account's school) to configure both the [SyncService] and
/// its [SupabaseSyncRemoteApi]. Falls back to [schoolsDao.get] only when
/// the auth provider has no currentSchool yet (early boot).
final syncServiceProvider = FutureProvider<SyncService>((ref) async {
  final db = ref.watch(databaseProvider);
  final securityService = ref.watch(securityServiceProvider);
  final authState = ref.watch(authProvider);

  // Prefer the authenticated school's serverId from auth state. Only fall
  // back to schoolsDao.get() (which just returns the first non-deleted row)
  // when auth state hasn't been loaded yet.
  String schoolId;
  if (authState.currentSchool?.serverId != null) {
    schoolId = authState.currentSchool!.serverId!;
  } else {
    final school = await db.schoolsDao.get();
    schoolId = school?.serverId ?? '';
  }

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
/// Sync runs automatically:
/// - When connectivity transitions from offline → online
/// - Periodically every 5 minutes while online
/// - Sync pauses when device goes offline
class SyncStatusNotifier extends Notifier<SyncStatusData> {
  Timer? _periodicSyncTimer;
  bool _wasOffline = true;
  bool _isSyncing = false;
  bool _initialized = false;

  @override
  SyncStatusData build() {
    if (_initialized) {
      return state;
    }
    _initialized = true;

    // Periodic background sync every 5 minutes while online.
    // Also polls connectivity to detect offline→online transitions
    // (replaces the onConnectivityChanged stream which can cause
    // PlatformException(0, NetworkManager::StartListen) on Android).
    _periodicSyncTimer ??= Timer.periodic(
      const Duration(minutes: 5),
      (_) async {
        await _pollConnectivity();
        if (state.isOnline && !_isSyncing) {
          _autoSync();
        }
      },
    );

    ref.onDispose(() {
      _periodicSyncTimer?.cancel();
      _periodicSyncTimer = null;
      _initialized = false;
    });

    // Trigger an initial sync after the widget tree is built so that
    // data (teachers, pending teachers, etc.) is available immediately
    // when the admin dashboard or any other screen first renders.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.mounted) {
        _autoSync();
      }
    });

    return const SyncStatusData(status: SyncStatus.offline);
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Polls connectivity and updates state if a transition occurred.
  Future<void> _pollConnectivity() async {
    await refresh();
    if (state.isOnline && _wasOffline) {
      _autoSync();
    }
    _wasOffline = !state.isOnline;
  }

  /// Sets the JWT on the remote API so edge function calls are authenticated.
  /// Returns the JWT, or null if not available.
  Future<String?> _setJwtOnRemoteApi(SyncService syncService) async {
    final authService = ref.read(authServiceProvider);
    final jwt = await authService.getValidAccessToken();
    if (jwt != null && jwt.isNotEmpty && syncService.remoteApi is SupabaseSyncRemoteApi) {
      (syncService.remoteApi as SupabaseSyncRemoteApi).setJwt(jwt);
    }
    return jwt;
  }

  /// Silent background sync — no error toasts, just status updates.
  Future<void> _autoSync() async {
    // Safety reset: if a previous sync never cleared _isSyncing, force-clear it
    if (_isSyncing) {
      _isSyncing = false;
    }
    _isSyncing = true;

    try {
      final isOnline = await PlatformHelper.isOnline();
      if (!isOnline) {
        state = SyncStatusData(
          status: SyncStatus.offline,
          lastSyncTime: state.lastSyncTime,
          pendingPushCount: state.pendingPushCount,
          pendingPullCount: state.pendingPullCount,
          conflictCount: state.conflictCount,
          isOnline: false,
        );
        return;
      }

      state = SyncStatusData(
        status: SyncStatus.syncing,
        lastSyncTime: state.lastSyncTime,
        pendingPushCount: state.pendingPushCount,
        pendingPullCount: state.pendingPullCount,
        conflictCount: state.conflictCount,
        isOnline: isOnline,
      );

      final syncService = await ref.read(syncServiceProvider.future);
      final jwt = await _setJwtOnRemoteApi(syncService);
      await syncService.onConnectivityRestored(jwt: jwt);
      await refresh();
      await ref.read(dailyCreditStateProvider.notifier).refresh();
      await ref.read(configServiceProvider).refresh();
      // Refresh in-memory school state so any tier/school-name change
      // from the sync pull is visible immediately (no re-login required).
      await ref.read(authProvider.notifier).refreshSchoolFromDb();
      // Invalidate lesson/exam list and count providers so the UI reflects
      // any new/updated data pulled during sync.
      ref.invalidate(lessonsListProvider);
      ref.invalidate(examsListProvider);
      ref.invalidate(recentLessonsProvider);
      ref.invalidate(lessonCountProvider);
      ref.invalidate(examCountProvider);
    } on SessionMismatchException {
      // Session was invalidated by a login on another device — force logout
      await ref.read(authProvider.notifier).manualLogout();
    } catch (e) {
      // Silent fail for auto-sync — no user-visible toasts
      state = SyncStatusData(
        status: SyncStatus.error,
        lastSyncTime: state.lastSyncTime,
        pendingPushCount: state.pendingPushCount,
        pendingPullCount: state.pendingPullCount,
        conflictCount: state.conflictCount,
        isOnline: state.isOnline,
      );
    } finally {
      _isSyncing = false;
    }
  }

  /// Trigger a full sync cycle (pull-merge-push) and update UI status.
  ///
  /// Sets the status to [SyncStatus.syncing], calls
  /// [SyncService.onConnectivityRestored()], then refreshes the display.
  /// On failure the status is set to [SyncStatus.error] and a snackbar is
  /// shown with the error message.
  Future<void> syncNow() async {
    // Safety reset: if a previous sync never cleared _isSyncing, force-clear it
    if (_isSyncing) {
      _isSyncing = false;
    }
    await refresh();
    final currentState = state;
    if (!currentState.isOnline) {
      return;
    }

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

      final jwt = await _setJwtOnRemoteApi(syncService);

      // Run the full sync cycle
      await syncService.onConnectivityRestored(jwt: jwt);
    } on SessionMismatchException {
      // Session was invalidated by a login on another device — force logout
      await ref.read(authProvider.notifier).manualLogout();
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
    await ref.read(dailyCreditStateProvider.notifier).refresh();
    await ref.read(configServiceProvider).refresh();
    // Refresh in-memory school state so any tier/school-name change
    // from the sync pull is visible immediately (no re-login required).
    await ref.read(authProvider.notifier).refreshSchoolFromDb();
    // Invalidate lesson/exam list and count providers so the UI reflects
    // any new/updated data pulled during sync.
    ref.invalidate(lessonsListProvider);
    ref.invalidate(examsListProvider);
    ref.invalidate(recentLessonsProvider);
    ref.invalidate(lessonCountProvider);
    ref.invalidate(examCountProvider);
  }

  /// Triggers a forced full resync.
  /// Returns true if there were push failures during the resync (unsaved changes
  /// may be lost when the full pull overwrites local data).
  Future<bool> forceFullResync() async {
    // Safety reset: if a previous sync never cleared _isSyncing, force-clear it
    if (_isSyncing) {
      _isSyncing = false;
    }
    await refresh();
    final currentState = state;
    if (!currentState.isOnline) {
      return false;
    }

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

      // Resolve SyncService
      final syncService = await ref.read(syncServiceProvider.future);
      final jwt = await _setJwtOnRemoteApi(syncService);

      // Run force full resync
      return await syncService.forceFullResync(jwt: jwt);
    } on SessionMismatchException {
      await ref.read(authProvider.notifier).manualLogout();
      return false;
    } catch (e, _) {
      state = SyncStatusData(
        status: SyncStatus.error,
        lastSyncTime: currentState.lastSyncTime,
        pendingPushCount: currentState.pendingPushCount,
        pendingPullCount: currentState.pendingPullCount,
        conflictCount: currentState.conflictCount,
        isOnline: currentState.isOnline,
      );

      final context = navigatorKey.currentContext;
      if (context != null && context.mounted) {
        showErrorToast(context: context, message: 'Resync failed: $e');
      }
      return false;
    } finally {
      // Refresh display state after sync attempt
      await refresh();
      await ref.read(dailyCreditStateProvider.notifier).refresh();
      await ref.read(configServiceProvider).refresh();
      await ref.read(authProvider.notifier).refreshSchoolFromDb();
    }
  }

  /// Refresh sync status from the database and service.
  Future<void> refresh() async {
    try {
      final config = await _db.securityConfigDao.get();
      final pendingQueue = await _db.syncQueueDao.pendingEntries();
      final conflicts = await (_db.select(_db.conflicts)
            ..where((t) => t.resolution.equals('unresolved')))
          .get();

      final isOnline = await PlatformHelper.isOnline();

      final syncStatus = _determineSyncStatus(config, isOnline);
      state = SyncStatusData(
        status: syncStatus,
        lastSyncTime: config.lastSyncAttemptTime,
        pendingPushCount: pendingQueue.length,
        pendingPullCount: 0, // Pull count tracked server-side
        conflictCount: conflicts.length,
        isOnline: isOnline,
      );
    } catch (_) {
      // Refresh failed (e.g. DB error) — preserve previous isOnline state
      // instead of hardcoding false, so real connectivity isn't overridden.
      state = SyncStatusData(
        status: SyncStatus.offline,
        lastSyncTime: state.lastSyncTime,
        pendingPushCount: state.pendingPushCount,
        pendingPullCount: state.pendingPullCount,
        conflictCount: state.conflictCount,
        isOnline: state.isOnline,
      );
    }
  }

  /// Determines the appropriate [SyncStatus] based on connectivity and
  /// last-sync time.  If the device is offline the status is always
  /// [SyncStatus.offline], regardless of how recently a sync completed.
  SyncStatus _determineSyncStatus(SecurityConfigData config, bool isOnline) {
    if (!isOnline) return SyncStatus.offline;
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
