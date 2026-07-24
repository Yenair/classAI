// lib/core/database/daos/exams_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/exams.dart';

part 'exams_dao.g.dart';

@DriftAccessor(tables: [Exams])
class ExamsDao extends DatabaseAccessor<AppDatabase>
    with _$ExamsDaoMixin {
  ExamsDao(AppDatabase db) : super(db);

  /// Get all non-deleted exams ordered by created date descending.
  Future<List<Exam>> getAll() {
    return (select(exams)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get all non-deleted exams for a specific teacher, ordered by created date descending.
  Future<List<Exam>> getAllForTeacher(String teacherServerId) {
    return (select(exams)
          ..where((t) => t.teacherServerId.equals(teacherServerId))
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get an exam by ID.
  Future<Exam?> getById(int id) async {
    final results = await (select(exams)..where((t) => t.id.equals(id))).get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Insert a new exam and return its auto-generated ID.
  Future<int> insertExam(ExamsCompanion companion) {
    return into(exams).insert(companion);
  }

  /// Update an existing exam with new content and metadata.
  Future<void> updateExam(int id, ExamsCompanion companion) {
    return (update(exams)..where((t) => t.id.equals(id))).write(companion);
  }

  /// Count non-deleted exams for a given school.
  Future<int> countNonDeletedBySchool(String schoolServerId) async {
    final query = selectOnly(exams)
      ..addColumns([exams.id.count()])
      ..where(exams.schoolServerId.equals(schoolServerId))
      ..where(exams.isDeleted.equals(false));
    final row = await query.getSingle();
    return row.read<int>(exams.id.count()) ?? 0;
  }

  /// Soft-delete an exam by marking it as deleted.
  Future<void> deleteExam(int id) {
    return (update(exams)..where((t) => t.id.equals(id))).write(
      ExamsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Find an existing exam by topic + subject + teacher to prevent duplicates.
  Future<Exam?> findByTopicSubjectTeacher({
    required String topic,
    required String subject,
    required String teacherServerId,
  }) async {
    final results = await (select(exams)
          ..where((t) => t.topic.equals(topic))
          ..where((t) => t.subject.equals(subject))
          ..where((t) => t.teacherServerId.equals(teacherServerId))
          ..where((t) => t.isDeleted.equals(false))
          ..limit(1))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Hard-delete only confirmed-synced rows for a given teacher.
  /// Used during logout to scope-clean the outgoing teacher's data
  /// while leaving unsynced (pending) rows intact (Option b).
  Future<void> deleteSyncedRowsByTeacher(String teacherServerId) {
    return (delete(exams)
          ..where((t) => t.teacherServerId.equals(teacherServerId))
          ..where((t) => t.serverId.isNotNull()))
        .go();
  }
}
