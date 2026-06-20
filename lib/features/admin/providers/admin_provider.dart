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
  final int generatedCount;
  final int completedCount;
  final String schemeStatus;
  final int completedWeeks;
  final int totalWeeks;

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
    this.generatedCount = 0,
    this.completedCount = 0,
    this.schemeStatus = 'none',
    this.completedWeeks = 0,
    this.totalWeeks = 0,
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

      // Look up the school by serverId from auth state rather than using
      // schoolsDao.get() (which returns the first non-deleted school). The
      // local DB may contain multiple school records, and the admin's actual
      // school may not be the first one — causing teachers to be stored under
      // the wrong schoolLocalId.
      final schoolServerId = authState.currentSchool?.serverId;
      int schoolLocalId;
      if (schoolServerId != null) {
        final schoolByServerId = await (_db.select(_db.schools)
              ..where((s) => s.serverId.equals(schoolServerId)))
            .getSingleOrNull();
        schoolLocalId = schoolByServerId?.localId ?? 0;
        if (schoolByServerId == null) {
          debugPrint('[admin] WARNING: school with serverId=$schoolServerId '
              'not found in local DB; using fallback');
        }
      } else {
        final school = await _db.schoolsDao.get();
        schoolLocalId = school?.localId ?? 0;
      }
      await _db.reconcileLegacyTeachers();
      final teachers = await _db.teachersDao.getBySchool(schoolLocalId);
      debugPrint(
        '[ADMIN-DEBUG] Teachers in local DB for school $schoolLocalId: ${teachers.length}',
      );
      final pendingTeachersFromDao =
          await _db.teachersDao.getPendingTeachers(schoolLocalId: schoolLocalId);
      debugPrint(
        '[ADMIN-DEBUG] Pending teachers for school $schoolLocalId: ${pendingTeachersFromDao.length}',
      );
      for (final t in pendingTeachersFromDao) {
        debugPrint(
          '[ADMIN-DEBUG] Pending: ${t.email}, '
          'forcePasswordReset=${t.forcePasswordReset}, '
          'tempPassword=${t.tempPassword}',
        );
      }
      final pendingItems = await _db.vaultItemsDao.getPendingApproval();

      // Build teacher data with real device counts, sync counts, conflicts
      final teacherDataList = <TeacherAdminData>[];
      final pendingTeacherList = <PendingTeacherData>[];
      final totalPendingCount = await _db.syncQueueDao.pendingCount();
      final conflictRows = await (_db.select(_db.conflicts)
            ..where((t) => t.resolution.equals('unresolved')))
          .get();
      final totalConflictCount = conflictRows.length;

      // Deduplicate teachers by serverId (keep first occurrence) so that
      // even if duplicates remain in the database, the count is accurate.
      final seenServerIds = <String>{};
      final uniqueTeachers = <Teacher>[];
      for (final t in teachers.where((t) => !t.isDeleted)) {
        if (t.serverId != null) {
          if (!seenServerIds.add(t.serverId!)) continue;
        }
        uniqueTeachers.add(t);
      }

      for (final t in uniqueTeachers) {
        final deviceCount =
            await _db.teacherDevicesDao.countActiveByTeacher(t.localId);
        final generatedCount = t.serverId != null
            ? await _db.lessonsDao.countByTeacher(t.serverId!)
            : 0;
        final completedCount = t.serverId != null
            ? await _db.lessonsDao.countCompletedByTeacher(t.serverId!)
            : 0;
        final schemeStats = await _loadSchemeProgressForTeacher(t);

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
          generatedCount: generatedCount,
          completedCount: completedCount,
          schemeStatus: schemeStats.schemeStatus,
          completedWeeks: schemeStats.completedWeeks,
          totalWeeks: schemeStats.totalWeeks,
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

  Future<_SchemeProgress> _loadSchemeProgressForTeacher(Teacher teacher) async {
    final teacherSchemes = await (_db.select(_db.schemeOfWork)
          ..where((s) => s.teacherId.equals(teacher.localId))
          ..orderBy([
            (s) => OrderingTerm(
                  expression: s.createdAt,
                  mode: OrderingMode.desc,
                )
          ]))
        .get();

    if (teacherSchemes.isEmpty) {
      return const _SchemeProgress.none();
    }

    final latestScheme = teacherSchemes.first;
    if (latestScheme.status != 'approved') {
      return _SchemeProgress(
        schemeStatus: latestScheme.status,
        completedWeeks: 0,
        totalWeeks: 0,
      );
    }

    final approvedSchemes = teacherSchemes
        .where((scheme) =>
            scheme.status == 'approved' &&
            scheme.subjectId == latestScheme.subjectId &&
            scheme.term == latestScheme.term)
        .toList();
    final totalWeeks = approvedSchemes.map((scheme) => scheme.weekNumber).toSet().length;

    if (teacher.serverId == null || totalWeeks == 0) {
      return _SchemeProgress(
        schemeStatus: 'approved',
        completedWeeks: 0,
        totalWeeks: totalWeeks,
      );
    }

    final approvedWeekNumbers =
        approvedSchemes.map((scheme) => scheme.weekNumber).toSet();
    final completedLessons = await (_db.select(_db.lessons)
          ..where((lesson) =>
              lesson.teacherServerId.equals(teacher.serverId!) &
              lesson.status.equals('completed')))
        .get();
    final completedWeeks = completedLessons
        .map((lesson) => lesson.week)
        .where(approvedWeekNumbers.contains)
        .toSet()
        .length;

    return _SchemeProgress(
      schemeStatus: 'approved',
      completedWeeks: completedWeeks,
      totalWeeks: totalWeeks,
    );
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

class _SchemeProgress {
  final String schemeStatus;
  final int completedWeeks;
  final int totalWeeks;

  const _SchemeProgress({
    required this.schemeStatus,
    required this.completedWeeks,
    required this.totalWeeks,
  });

  const _SchemeProgress.none()
      : schemeStatus = 'none',
        completedWeeks = 0,
        totalWeeks = 0;
}

final adminDashboardProvider =
    NotifierProvider<AdminDashboardNotifier, AdminDashboardData>(
  AdminDashboardNotifier.new,
);
