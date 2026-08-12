// test/sync/vault_queue_cleanup_test.dart
//
// Unit tests for removeVaultSyncQueueEntries (lib/core/services/
// vault_queue_cleanup.dart). Verifies that:
//   - fake vault_items sync-queue entries are removed,
//   - entries for OTHER tables (e.g. lessons) are left untouched,
//   - running the cleanup again is a safe no-op (idempotent).
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/vault_queue_cleanup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  Future<void> _insertEntry({
    required String queueTable,
    required int recordLocalId,
    required String operation,
  }) {
    return db.syncQueueDao.insertEntry(
      queueTable: queueTable,
      recordLocalId: recordLocalId,
      operation: operation,
      payload: {'id': recordLocalId},
    );
  }

  test('removes exactly the vault_items sync-queue entries', () async {
    await _insertEntry(queueTable: 'vault_items', recordLocalId: 101, operation: 'INSERT');
    await _insertEntry(queueTable: 'vault_items', recordLocalId: 102, operation: 'UPDATE');
    await _insertEntry(queueTable: 'vault_items', recordLocalId: 103, operation: 'DELETE');
    // Entries for other tables that must be preserved.
    await _insertEntry(queueTable: 'lessons', recordLocalId: 201, operation: 'INSERT');
    await _insertEntry(queueTable: 'scheme_of_work', recordLocalId: 301, operation: 'INSERT');

    final deleted = await removeVaultSyncQueueEntries(db);

    expect(deleted, 3, reason: 'only the three vault_items entries are deleted');

    final remaining = await db.select(db.syncQueue).get();
    expect(remaining, hasLength(2));
    for (final row in remaining) {
      expect(row.queueTable, isNot('vault_items'),
          reason: 'no vault_items rows may survive the cleanup');
    }
    final remainingTables = remaining.map((r) => r.queueTable).toSet();
    expect(remainingTables, contains('lessons'));
    expect(remainingTables, contains('scheme_of_work'));
  });

  test('is idempotent — a second run deletes nothing', () async {
    await _insertEntry(queueTable: 'vault_items', recordLocalId: 1, operation: 'INSERT');
    await _insertEntry(queueTable: 'vault_items', recordLocalId: 2, operation: 'UPDATE');

    expect(await removeVaultSyncQueueEntries(db), 2);
    // Second run: nothing left to delete.
    expect(await removeVaultSyncQueueEntries(db), 0);

    expect(await db.syncQueueDao.pendingCount(), 0);
  });
}
