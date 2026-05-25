// lib/features/admin/providers/admin_provider.dart
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Data for a single teacher in the admin dashboard list.
class TeacherAdminData {
  final int localId;
  final String? serverId;
  final String email;
  final String teacherName;
  final String role;
  final DateTime? lastSyncTime;
  final int deviceCount;
  final bool isActive;
  final int pendingSyncCount;
  final int conflictCount;
  final String? schoolSubscriptionTier;

  const TeacherAdminData({
    required this.localId,
    this.serverId,
    required this.email,
    required this.teacherName,
    required this.role,
    this.lastSyncTime,
    this.deviceCount = 0,
    this.isActive = true,
    this.pendingSyncCount = 0,
    this.conflictCount = 0,
    this.schoolSubscriptionTier,
  });

  /// Status indicator color:
  ///   green  (<1 hour since last sync)
  ///   yellow (1-24 hours)
  ///   red    (>24 hours)
  ///   gray   (>7 days or null)
  String get statusColor {
    if (lastSyncTime == null) return 'gray';
    final diff = DateTime.now().difference(lastSyncTime!);
    if (diff.inHours < 1) return 'green';
    if (diff.inHours < 24) return 'yellow';
    if (diff.inDays < 7) return 'red';
    return 'gray';
  }

  /// Formatted relative timestamp string for display.
  String get formattedLastSync {
    if (lastSyncTime == null) return 'Never';
    final diff = DateTime.now().difference(lastSyncTime!);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${diff.inDays} days ago';
  }
}

/// Data exposed to the admin dashboard screens.
class AdminDashboardData {
  final List<TeacherAdminData> teachers;
  final int pendingVaultApprovals;
  final bool loading;
  final String? errorMessage;

  const AdminDashboardData({
    this.teachers = const [],
    this.pendingVaultApprovals = 0,
    this.loading = false,
    this.errorMessage,
  });
}

/// Notifier that provides admin dashboard data.
class AdminDashboardNotifier extends Notifier<AdminDashboardData> {
  @override
  AdminDashboardData build() {
    return const AdminDashboardData(loading: true);
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Refresh all admin dashboard data.
  Future<void> refresh() async {
    state = const AdminDashboardData(loading: true);

    try {
      // Only load teachers belonging to the current admin's school
      final authState = ref.read(authProvider);
      final schoolLocalId = authState.currentSchool?.localId ?? 0;
      final teachers = await _db.teachersDao.getBySchool(schoolLocalId);
      final pendingItems = await _db.vaultItemsDao.getPendingApproval();

      // Build teacher data with real device counts, sync counts, conflicts
      final teacherDataList = <TeacherAdminData>[];
      final totalPendingCount = await _db.syncQueueDao.pendingCount();
      final conflictRows = await (_db.select(_db.conflicts)
            ..where((t) => t.resolution.equals('unresolved')))
          .get();
      final totalConflictCount = conflictRows.length;

      for (final t in teachers.where((t) => !t.isDeleted)) {
        final deviceCount =
            await _db.teacherDevicesDao.countActiveByTeacher(t.localId);

        teacherDataList.add(TeacherAdminData(
          localId: t.localId,
          serverId: t.serverId,
          email: t.email,
          teacherName: t.teacherName,
          role: t.role,
          lastSyncTime: t.updatedAt,
          isActive: t.isActive,
          deviceCount: deviceCount,
          pendingSyncCount: totalPendingCount,
          conflictCount: totalConflictCount,
        ));
      }

      state = AdminDashboardData(
        teachers: teacherDataList,
        pendingVaultApprovals: pendingItems.length,
      );
    } catch (e) {
      state = AdminDashboardData(
        errorMessage: 'Failed to load admin data: $e',
      );
    }
  }

  /// Deactivate a teacher account.
  Future<void> deactivateTeacher(int localId) async {
    await (_db.update(_db.teachers)..where((t) => t.localId.equals(localId)))
        .write(TeachersCompanion(
      isActive: Value(false),
    ));
    await refresh();
  }

  /// Reactivate a teacher account.
  Future<void> reactivateTeacher(int localId) async {
    await (_db.update(_db.teachers)..where((t) => t.localId.equals(localId)))
        .write(TeachersCompanion(
      isActive: Value(true),
    ));
    await refresh();
  }
}

final adminDashboardProvider =
    NotifierProvider<AdminDashboardNotifier, AdminDashboardData>(
  AdminDashboardNotifier.new,
);
