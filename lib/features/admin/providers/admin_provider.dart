// lib/features/admin/providers/admin_provider.dart
import 'package:flutter/foundation.dart';
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

/// Data for a pending teacher (hasn't logged in yet) with their temp password.
class PendingTeacherData {
  final int localId;
  final String? serverId;
  final String email;
  final String teacherName;
  final String role;
  final String? tempPassword;

  const PendingTeacherData({
    required this.localId,
    this.serverId,
    required this.email,
    required this.teacherName,
    required this.role,
    this.tempPassword,
  });
}

/// Data exposed to the admin dashboard screens.
class AdminDashboardData {
  final List<TeacherAdminData> teachers;
  final List<PendingTeacherData> pendingTeachers;
  final int pendingVaultApprovals;
  final bool loading;
  final String? errorMessage;

  const AdminDashboardData({
    this.teachers = const [],
    this.pendingTeachers = const [],
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
      // Only load teachers belonging to the current admin's school.
      // IMPORTANT: authState.currentSchool.localId is always 0 because the
      // School object in AuthResult is constructed with a hardcoded localId: 0
      // (see auth_service.dart). Always read the real auto-generated localId
      // from the local database.
      final authState = ref.read(authProvider);
      debugPrint('[admin] refresh: authState.state=${authState.state}, '
          'currentSchool=${authState.currentSchool?.toString() ?? 'null'}');

      final school = await _db.schoolsDao.get();
      final schoolLocalId = school?.localId ?? 0;
      final teachers = await _db.teachersDao.getBySchool(schoolLocalId);
      final pendingTeachersFromDao =
          await _db.teachersDao.getPendingTeachers(schoolLocalId: schoolLocalId);
      final pendingItems = await _db.vaultItemsDao.getPendingApproval();

      // Build teacher data with real device counts, sync counts, conflicts
      final teacherDataList = <TeacherAdminData>[];
      final pendingTeacherList = <PendingTeacherData>[];
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

      // Build pending teacher list using the dedicated DAO method
      // (now school-filtered at the query level)
      for (final t in pendingTeachersFromDao) {
        pendingTeacherList.add(PendingTeacherData(
          localId: t.localId,
          serverId: t.serverId,
          email: t.email,
          teacherName: t.teacherName,
          role: t.role,
          tempPassword: t.tempPassword,
        ));
      }

      debugPrint(
        '[admin] refresh: schoolLocalId=$schoolLocalId, '
        '${teachers.length} active teachers, '
        '${pendingTeachersFromDao.length} pending teachers for this school',
      );

      state = AdminDashboardData(
        teachers: teacherDataList,
        pendingTeachers: pendingTeacherList,
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
