// lib/core/database/daos/lessons_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/lessons.dart';

part 'lessons_dao.g.dart';

@DriftAccessor(tables: [Lessons])
class LessonsDao extends DatabaseAccessor<AppDatabase>
    with _$LessonsDaoMixin {
  LessonsDao(AppDatabase db) : super(db);

  /// Get all lessons ordered by week.
  Future<List<Lesson>> getAll() {
    return (select(lessons)
          ..orderBy([(t) => OrderingTerm(expression: t.week, mode: OrderingMode.asc)]))
        .get();
  }

  /// Get the most recent lessons, ordered by createdAt descending, limited to [limit].
  Future<List<Lesson>> getRecentLessons({int limit = 5}) {
    return (select(lessons)
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
}
