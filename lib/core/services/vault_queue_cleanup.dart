// lib/core/services/vault_queue_cleanup.dart
//
// One-shot cleanup helper that drops stale sync-queue entries for the
// `vault_items` table.
//
// Some devices accumulated `vault_items` entries in the local sync_queue that
// will never succeed (vault_items is not a per-school pushable table the same
// way lessons/scheme_of_work are) and they jam the queue / retry forever.
//
// This utility is intentionally NOT wired into app startup or any screen or
// provider. It is invoked manually (see the throwaway runner in
// test/run_vault_cleanup_once.dart) to clear those entries on the real device.
//
// It is idempotent: running it multiple times is safe (the second run simply
// finds nothing left to delete and returns 0).
import 'package:classai/core/database/database.dart';

/// Deletes all rows from the `sync_queue` table whose `queue_table` is
/// `'vault_items'`. Returns the number of deleted rows.
Future<int> removeVaultSyncQueueEntries(AppDatabase db) {
  return (db.delete(db.syncQueue)
        ..where((t) => t.queueTable.equals('vault_items')))
      .go();
}
