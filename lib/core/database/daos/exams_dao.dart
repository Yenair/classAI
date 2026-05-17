// lib/core/database/daos/exams_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/exams.dart';

part 'exams_dao.g.dart';

@DriftAccessor(tables: [Exams])
class ExamsDao extends DatabaseAccessor<AppDatabase>
    with _$ExamsDaoMixin {
  ExamsDao(AppDatabase db) : super(db);

  /// Get all exams ordered by created date descending.
  Future<List<Exam>> getAll() {
    return (select(exams)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  /// Get an exam by ID.
  Future<Exam?> getById(int id) async {
    final results = await (select(exams)..where((t) => t.id.equals(id))).get();
    return results.isNotEmpty ? results.first : null;
  }
}
