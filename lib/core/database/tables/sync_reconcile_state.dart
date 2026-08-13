import 'package:drift/drift.dart';

/// Tracks how many consecutive pull cycles a local row has been in the
/// "missing from the server" state during full-table reconciliation.
///
/// Used for two purposes (see plans/sync_full_table_reconciliation.md):
///   * stop-limit (Fix 6): after `maxAttempts` missing cycles the row is
///     flagged for manual review instead of being re-queued forever;
///   * progress_logs one-shot (Fix 1): maxAttempts is 1, so a progress log
///     is never auto-requeued more than once.
///
/// A row is deleted as soon as the local row matches the server at Tier 1
/// (server_id) or Tier 2 (natural key), so tracking only exists while a row
/// is actively failing to reconcile.
class SyncReconcileState extends Table {
  IntColumn get id => integer().autoIncrement()();
  // Named `recordTable` (not `tableName`) to avoid shadowing drift's own
  // Table.tableName getter.
  TextColumn get recordTable => text()();
  IntColumn get localId => integer()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get lastAttemptedAt => dateTime().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
        {recordTable, localId},
      ];
}
