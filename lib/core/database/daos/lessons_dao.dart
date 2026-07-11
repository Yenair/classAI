// lib/core/database/daos/lessons_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/lessons.dart';

part 'lessons_dao.g.dart';

@DriftAccessor(tables: [Lessons])
class LessonsDao extends DatabaseAccessor<AppDatabase>
    with _$LessonsDaoMixin {
  LessonsDao(AppDatabase db) : super(db);

  /// Get all **non‑deleted** lessons ordered by week.
  Future<List<Lesson>> getAll() {
    return (select(lessons)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.week, mode: OrderingMode.asc)]))
        .get();
  }

  /// Get the most recent **non‑deleted** lessons, ordered by createdAt descending, limited to [limit].
  Future<List<Lesson>> getRecentLessons({int limit = 5}) {
    return (select(lessons)
          ..where((t) => t.isDeleted.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)])
          ..limit(limit))
        .get();
  }

  /// Get lessons by subject (ID is the subject name string in the lessons table).
  Future<List<Lesson>> getBySubject(int subjectId) {
    return (select(lessons)
          ..where((t) => t.subject.equals(subjectId.toString()))
          ..orderBy([(t) => OrderingTerm(expression: t.week, mode: OrderingMode.asc)]))
        .get();
  }

  /// Insert a new lesson and return its auto-generated ID.
  Future<int> insertLesson(LessonsCompanion companion) {
    return into(lessons).insert(companion);
  }

  /// Get a lesson by its local ID.
  Future<Lesson?> getById(int id) async {
    final results = await (select(lessons)..where((t) => t.id.equals(id))).get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Count lessons by teacher server ID.
  Future<int> countByTeacher(String teacherServerId) async {
    final query = selectOnly(lessons)
      ..addColumns([lessons.id.count()])
      ..where(lessons.teacherServerId.equals(teacherServerId));
    final row = await query.getSingle();
    return row.read<int>(lessons.id.count()) ?? 0;
  }

  /// Count completed lessons by teacher server ID.
  Future<int> countCompletedByTeacher(String teacherServerId) async {
    final query = selectOnly(lessons)
      ..addColumns([lessons.id.count()])
      ..where(lessons.teacherServerId.equals(teacherServerId))
      ..where(lessons.status.equals('completed'));
    final row = await query.getSingle();
    return row.read<int>(lessons.id.count()) ?? 0;
  }

  /// Update a lesson's status.
  Future<void> updateStatus(int id, String status) {
    return (update(lessons)..where((t) => t.id.equals(id))).write(
      LessonsCompanion(
        status: Value(status),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Find an existing lesson by topic + subject + week + teacher to prevent duplicates.
  Future<Lesson?> findByTopicSubjectWeekTeacher({
    required String topic,
    required String subject,
    required int week,
    required String teacherServerId,
  }) async {
    final results = await (select(lessons)
          ..where((t) => t.topic.equals(topic))
          ..where((t) => t.subject.equals(subject))
          ..where((t) => t.week.equals(week))
          ..where((t) => t.teacherServerId.equals(teacherServerId))
          ..where((t) => t.isDeleted.equals(false))
          ..limit(1))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Update an existing lesson with new content and metadata.
  Future<void> updateLesson(int id, LessonsCompanion companion) {
    return (update(lessons)..where((t) => t.id.equals(id))).write(companion);
  }

  /// Count non-deleted lessons for a given school.
  Future<int> countNonDeletedBySchool(String schoolServerId) async {
    final query = selectOnly(lessons)
      ..addColumns([lessons.id.count()])
      ..where(lessons.schoolServerId.equals(schoolServerId))
      ..where(lessons.isDeleted.equals(false));
    final row = await query.getSingle();
    return row.read<int>(lessons.id.count()) ?? 0;
  }

  /// Soft-delete a lesson by marking it as deleted.
  Future<void> deleteLesson(int id) {
    return (update(lessons)..where((t) => t.id.equals(id))).write(
      LessonsCompanion(
        isDeleted: const Value(true),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }
}
