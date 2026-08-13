import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/sync_reconcile_state.dart';

part 'sync_reconcile_state_dao.g.dart';

@DriftAccessor(tables: [SyncReconcileState])
class SyncReconcileStateDao extends DatabaseAccessor<AppDatabase>
    with _$SyncReconcileStateDaoMixin {
  SyncReconcileStateDao(AppDatabase db) : super(db);

  Future<SyncReconcileStateData?> getFor(String tableName, int localId) {
    return (select(syncReconcileState)
          ..where((t) =>
              t.recordTable.equals(tableName) & t.localId.equals(localId)))
        .getSingleOrNull();
  }

  Future<List<SyncReconcileStateData>> getAll() {
    return select(syncReconcileState).get();
  }

  /// Records one reconciliation re-queue attempt for (table, localId),
  /// creating or incrementing the tracking row. Returns the new attempt count.
  Future<int> recordAttempt(
    String tableName,
    int localId, {
    DateTime? at,
  }) async {
    final existing = await getFor(tableName, localId);
    final now = at ?? DateTime.now();
    if (existing == null) {
      await into(syncReconcileState).insert(
        SyncReconcileStateCompanion.insert(
          recordTable: tableName,
          localId: localId,
          attempts: const Value(1),
          lastAttemptedAt: Value(now),
          updatedAt: Value(now),
        ),
      );
      return 1;
    }
    await (update(syncReconcileState)..where((t) => t.id.equals(existing.id)))
        .write(
      SyncReconcileStateCompanion(
        attempts: Value(existing.attempts + 1),
        lastAttemptedAt: Value(now),
        updatedAt: Value(now),
      ),
    );
    return existing.attempts + 1;
  }

  /// Removes tracking once the local row matches the server (Tier 1/2).
  Future<void> clearFor(String tableName, int localId) async {
    await (delete(syncReconcileState)
          ..where((t) =>
              t.recordTable.equals(tableName) & t.localId.equals(localId)))
        .go();
  }
}
