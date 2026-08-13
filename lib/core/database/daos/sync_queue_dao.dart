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

  Future<void> incrementAttempts(
    int id, {
    DateTime? lastAttemptAt,
    DateTime? nextRetryAt,
  }) async {
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
        nextRetryAt: nextRetryAt != null
            ? Value(nextRetryAt)
            : const Value.absent(),
      ),
      );
  }

  /// Resets a single pending entry's retry state after its dependency was
  /// repaired (e.g. a missing subject healed by the subject self-heal):
  /// next_retry_at = NULL (clears the cooldown), attempts = 0, and
  /// last_attempt_at = NULL. is_terminal is not touched — callers only pass
  /// pending rows, which stay pending and become due for push on the next
  /// cycle. Idempotent: re-running on an already-reset row is a no-op.
  Future<void> resetRetryState(int entryId) async {
    await (update(syncQueue)..where((t) => t.id.equals(entryId))).write(
      SyncQueueCompanion(
        nextRetryAt: const Value(null),
        attempts: const Value(0),
        lastAttemptAt: const Value(null),
      ),
    );
  }

  /// One-time recovery for legacy terminal rows that were dropped purely
  /// because a retryable failure exhausted the old 5-attempt cap.
  ///
  /// Resets ONLY rows whose [lastError] carries the precise server signal for
  /// this failure class (Postgres NOT NULL violation — the server returned
  /// `retryable: true` with exactly this message while the INSERT was being
  /// rejected). Rows terminal for any other reason are untouched.
  ///
  /// Idempotent: reset rows no longer match `is_terminal = true`, so a second
  /// run returns 0. Returns the number of rows reset so callers can log it.
  Future<int> recoverRetryableTerminalRows() async {
    final matching = await (select(syncQueue)
          ..where((t) =>
              t.isTerminal.equals(true) &
              t.lastError.isNotNull() &
              t.lastError.cast<String>().like('%violates not-null constraint%')))
        .get();
    if (matching.isEmpty) {
      return 0;
    }
    final now = DateTime.now();
    final ids = matching.map((r) => r.id).toList();
    await (update(syncQueue)..where((t) => t.id.isIn(ids))).write(
      SyncQueueCompanion(
        isTerminal: const Value(false),
        attempts: const Value(0),
        nextRetryAt: const Value(null),
        failedAt: const Value(null),
        lastAttemptAt: Value(now),
        // last_error is deliberately kept for visibility.
      ),
    );
    return matching.length;
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

  /// True when a non-terminal INSERT entry for (table, localId) is already
  /// pending. Used by the push engine to detect an UPDATE that is superseded
  /// by a pending INSERT for the same local row (the INSERT will create the
  /// server row, so the UPDATE can never apply).
  Future<bool> hasPendingInsertFor(String table, int localId) async {
    final rows = await (select(syncQueue)
          ..where((t) =>
              t.isTerminal.equals(false) &
              t.queueTable.equals(table) &
              t.recordLocalId.equals(localId) &
              t.operation.equals('INSERT'))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  /// Replaces a queue entry's stored payload — e.g. an UPDATE converted to a
  /// clean INSERT payload by the push engine — so a retry pushes the new
  /// payload and the success-path version snapshot matches what was sent.
  Future<void> updateEntryPayload(int id, Map<String, dynamic> payload) async {
    await (update(syncQueue)..where((t) => t.id.equals(id))).write(
      SyncQueueCompanion(payload: Value(jsonEncode(payload))),
    );
  }
}
