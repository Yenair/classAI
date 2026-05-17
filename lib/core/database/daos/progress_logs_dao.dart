// lib/core/database/daos/progress_logs_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/progress_logs.dart';

part 'progress_logs_dao.g.dart';

@DriftAccessor(tables: [ProgressLogs])
class ProgressLogsDao extends DatabaseAccessor<AppDatabase>
    with _$ProgressLogsDaoMixin {
  ProgressLogsDao(AppDatabase db) : super(db);

  /// Get all progress logs.
  Future<List<ProgressLog>> getAll() {
    return (select(progressLogs)).get();
  }
}
