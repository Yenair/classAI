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
          ..where((t) => t.isTerminal.equals(false))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.isEmergency,
                  mode: OrderingMode.desc,
                ),
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .get();
  }

  Future<List<SyncQueueData>> terminalEntries({int limit = 20}) {
    return (select(syncQueue)
          ..where((t) => t.isTerminal.equals(true))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.failedAt,
                  mode: OrderingMode.desc,
                ),
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
          ])
          ..limit(limit))
        .get();
  }

  Future<void> incrementAttempts(int id, {DateTime? lastAttemptAt}) async {
    final rows = await (select(syncQueue)..where((t) => t.id.equals(id)))
        .get();
    if (rows.isEmpty) {
      // Entry was already removed (e.g. by another code path after success),
      // so there's nothing to increment. Silently ignore.
      return;
    }
    final current = rows.first;
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        attempts: Value(current.attempts + 1),
        lastAttemptAt: Value(lastAttemptAt ?? DateTime.now()),
      ),
      );
  }

  Future<void> markTerminalFailure(
    int id, {
    String? lastError,
    DateTime? failedAt,
  }) async {
    final rows = await (select(syncQueue)..where((t) => t.id.equals(id)))
        .get();
    if (rows.isEmpty) {
      return;
    }
    final now = DateTime.now();
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(
        isTerminal: const Value(true),
        lastError: Value(lastError),
        failedAt: Value(failedAt ?? now),
        lastAttemptAt: Value(now),
      ),
    );
  }

  Future<void> deleteById(int id) async {
    await (delete(syncQueue)..where((t) => t.id.equals(id))).go();
  }

  /// Count all pending (un-synced) entries in the queue.
  Future<int> pendingCount() async {
    final rows = await (select(syncQueue)
          ..where((t) => t.isTerminal.equals(false)))
        .get();
    return rows.length;
  }

  /// Count pending entries for a specific table (e.g. teacher scope).
  Future<int> pendingCountForTable(String tableName) async {
    final rows = await (select(syncQueue)
          ..where((t) =>
              t.queueTable.equals(tableName) &
              t.isTerminal.equals(false)))
        .get();
    return rows.length;
  }
}
