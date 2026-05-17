// lib/core/database/daos/teacher_subjects_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/teacher_subjects.dart';

part 'teacher_subjects_dao.g.dart';

@DriftAccessor(tables: [TeacherSubjects])
class TeacherSubjectsDao extends DatabaseAccessor<AppDatabase>
    with _$TeacherSubjectsDaoMixin {
  TeacherSubjectsDao(AppDatabase db) : super(db);

  /// Insert a teacher-subject assignment.
  Future<int> insert({
    required int teacherId,
    required int subjectId,
  }) async {
    return into(teacherSubjects).insert(
      TeacherSubjectsCompanion.insert(
        teacherLocalId: teacherId,
        subjectId: subjectId,
      ),
    );
  }

  /// Get all subject IDs assigned to a teacher.
  Future<List<int>> getSubjectIdsForTeacher(int teacherLocalId) async {
    final rows = await (select(teacherSubjects)
          ..where((t) => t.teacherLocalId.equals(teacherLocalId)))
        .get();
    return rows.map((r) => r.subjectId).toList();
  }

  /// Get all teacher IDs assigned to a subject.
  Future<List<int>> getTeacherIdsForSubject(int subjectId) async {
    final rows = await (select(teacherSubjects)
          ..where((t) => t.subjectId.equals(subjectId)))
        .get();
    return rows.map((r) => r.teacherLocalId).toList();
  }

  /// Remove a teacher-subject assignment.
  Future<void> deleteAssignment({
    required int teacherId,
    required int subjectId,
  }) async {
    await (delete(teacherSubjects)
          ..where((t) => t.teacherLocalId.equals(teacherId))
          ..where((t) => t.subjectId.equals(subjectId)))
        .go();
  }

  /// Remove all assignments for a teacher.
  Future<void> deleteAllForTeacher(int teacherLocalId) async {
    await (delete(teacherSubjects)
          ..where((t) => t.teacherLocalId.equals(teacherLocalId)))
        .go();
  }
}
