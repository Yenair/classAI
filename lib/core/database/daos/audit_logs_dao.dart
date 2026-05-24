import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/audit_logs.dart';

part 'audit_logs_dao.g.dart';

@DriftAccessor(tables: [AuditLogs])
class AuditLogsDao extends DatabaseAccessor<AppDatabase>
    with _$AuditLogsDaoMixin {
  AuditLogsDao(AppDatabase db) : super(db);

  /// Insert a new audit log entry.
  Future<int> insert(AuditLogsCompanion companion) {
    return into(auditLogs).insert(companion);
  }

  /// Get all audit logs for a teacher.
  Future<List<AuditLog>> getByTeacher(String teacherId) {
    return (select(auditLogs)
          ..where((a) => a.teacherId.equals(teacherId))
          ..orderBy([
            (a) =>
                OrderingTerm(expression: a.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Get all audit logs for a school.
  Future<List<AuditLog>> getBySchool(String schoolId) {
    return (select(auditLogs)
          ..where((a) => a.schoolId.equals(schoolId))
          ..orderBy([
            (a) =>
                OrderingTerm(expression: a.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
  }

  /// Get audit logs by action type.
  Future<List<AuditLog>> getByAction(String action) {
    return (select(auditLogs)
          ..where((a) => a.action.equals(action))
          ..orderBy([
            (a) =>
                OrderingTerm(expression: a.createdAt, mode: OrderingMode.desc)
          ]))
        .get();
  }
}
