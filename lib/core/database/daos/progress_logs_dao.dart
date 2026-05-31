// lib/core/database/daos/progress_logs_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/progress_logs.dart';

part 'progress_logs_dao.g.dart';

@DriftAccessor(tables: [ProgressLogs])
class ProgressLogsDao extends DatabaseAccessor<AppDatabase>
    with _$ProgressLogsDaoMixin {
  ProgressLogsDao(AppDatabase db) : super(db);

  Future<List<ProgressLog>> getAll() {
    return (select(progressLogs)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  Future<List<ProgressLog>> getByTeacher(int teacherId) {
    return (select(progressLogs)
          ..where((t) => t.teacherId.equals(teacherId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  Future<int> insert(ProgressLogsCompanion companion) {
    return into(progressLogs).insert(companion);
  }
}
