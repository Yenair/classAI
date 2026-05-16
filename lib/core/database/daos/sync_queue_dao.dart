import 'dart:convert';
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/sync_queue.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(AppDatabase db) : super(db);

  Future<void> insertEntry({
    required String queueTable,
    required int recordLocalId,
    required String operation,
    required Map<String, dynamic> payload,
    int attempts = 0,
    bool isEmergency = false,
  }) async {
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        queueTable: queueTable,
        recordLocalId: recordLocalId,
        operation: operation,
        payload: jsonEncode(payload),
        attempts: Value(attempts),
        isEmergency: Value(isEmergency),
      ),
    );
  }

  Future<List<SyncQueueData>> pendingEntries() {
    return (select(syncQueue)
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.isEmergency,
                  mode: OrderingMode.desc,
                ),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .get();
  }

  Future<void> incrementAttempts(int id, {DateTime? lastAttemptAt}) async {
    final current = await (select(syncQueue)..where((t) => t.id.equals(id)))
        .getSingle();
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        attempts: Value(current.attempts + 1),
        lastAttemptAt: Value(lastAttemptAt ?? DateTime.now()),
      ),
    );
  }

  Future<void> deleteById(int id) async {
    await (delete(syncQueue)..where((t) => t.id.equals(id))).go();
  }
}
