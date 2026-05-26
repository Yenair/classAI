// lib/core/database/daos/teachers_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/teachers.dart';

part 'teachers_dao.g.dart';

@DriftAccessor(tables: [Teachers])
class TeachersDao extends DatabaseAccessor<AppDatabase>
    with _$TeachersDaoMixin {
  TeachersDao(AppDatabase db) : super(db);

  /// Get all non-deleted teachers.
  Future<List<Teacher>> getAll() {
    return (select(teachers)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.teacherName, mode: OrderingMode.asc)]))
        .get();
  }

  /// Get a teacher by local ID.
  Future<Teacher?> getById(int localId) async {
    final results = await (select(teachers)
          ..where((t) => t.localId.equals(localId)))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Get teachers for a school.
  Future<List<Teacher>> getBySchool(int schoolLocalId) {
    return (select(teachers)
          ..where((t) => t.schoolLocalId.equals(schoolLocalId))
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.teacherName, mode: OrderingMode.asc)]))
        .get();
  }

  /// Get all teachers with forcePasswordReset set to true (pending login).
  Future<List<Teacher>> getPendingTeachers() {
    return (select(teachers)
          ..where((t) => t.forcePasswordReset.equals(true)))
        .get();
  }
}
