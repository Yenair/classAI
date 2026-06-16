import '../database/database.dart';
import 'auth_service.dart';

/// Service for bulk administrative operations.
///
/// Depends only on [AppDatabase] for local operations.
class BulkOperationsService {
  final AppDatabase _db;

  BulkOperationsService(this._db);

  /// Assign one subject to multiple teachers.
  Future<void> bulkAssignSubject({
    required int subjectId,
    required List<int> teacherIds,
  }) async {
    await _db.transaction(() async {
      for (final teacherId in teacherIds) {
        await _db.teacherSubjectsDao.insert(
          teacherId: teacherId,
          subjectId: subjectId,
        );
      }
    });
  }

  /// Generate recovery codes for multiple teachers.
  /// Requires online connection to server.
  Future<Map<int, String>> bulkGenerateRecoveryCodes({
    required int adminId,
    required List<int> teacherIds,
    required AuthService authService,
  }) async {
    final results = <int, String>{};
    for (final teacherId in teacherIds) {
      try {
        final code = await authService.generateTeacherRecoveryCode(
          teacherId.toString(),
          adminId.toString(),
        );
        results[teacherId] = code;
      } catch (e) {
        results[teacherId] = 'FAILED: $e';
      }
    }
    return results;
  }

  /// Bulk approve/reject vault items.
  Future<void> bulkApproveVaultItems({
    required List<int> vaultItemIds,
    required bool approved,
    String? rejectionReason,
  }) async {
    await _db.transaction(() async {
      for (final id in vaultItemIds) {
        if (approved) {
          await _db.vaultItemsDao.approve(id, approvedAt: DateTime.now());
        } else {
          await _db.vaultItemsDao.reject(id, rejectionReason ?? 'Rejected');
        }
      }
    });
  }
}
