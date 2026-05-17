import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

Future<void> _seedConfig(AppDatabase db) async {
  await db.securityConfigDao.updateConfig(
    syncCursor: null,
    lastRealtimeEventId: 0,
    syncCooldownUntil: null,
  );
}

void main() {
  late AppDatabase db;
  late FakeSyncRecordStore store;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    await _seedConfig(db);
    store = FakeSyncRecordStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('emergency queue preserved on force logout', () async {
    // Insert emergency queue entries
    await db.syncQueueDao.insertEntry(
      queueTable: 'schools',
      recordLocalId: 1,
      operation: 'INSERT',
      payload: {'local_id': 1, 'data': {'schoolName': 'Emergency School'}},
      isEmergency: true,
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'subjects',
      recordLocalId: 2,
      operation: 'INSERT',
      payload: {'local_id': 2, 'data': {'name': 'Emergency Math'}},
      isEmergency: true,
    );

    // Insert a normal (non-emergency) entry
    await db.syncQueueDao.insertEntry(
      queueTable: 'lessons',
      recordLocalId: 3,
      operation: 'UPDATE',
      payload: {'local_id': 3, 'data': {'title': 'Normal lesson'}},
      isEmergency: false,
    );

    expect(await db.syncQueueDao.pendingEntries(), hasLength(3));

    final remote = FakeSyncRemoteApi(
      pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
      pushResponses: [
        SyncPushResponse(
          results: [
            SyncPushResult(
              localId: 1,
              status: 'error',
              serverId: null,
              retryable: false,
            ),
            SyncPushResult(
              localId: 2,
              status: 'error',
              serverId: null,
              retryable: false,
            ),
            SyncPushResult(
              localId: 3,
              status: 'error',
              serverId: null,
              retryable: false,
            ),
          ],
        ),
      ],
      realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
    );

    final security = TrackingSecurityService();
    final service = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: security,
      remoteApi: remote,
      store: store,
      mergeEngine: MergeEngine(),
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
      accountActive: false,
    );

    await service.onConnectivityRestored();

    // Clear session simulates force logout
    await security.clearSessionKey();

    expect(security.clearSessionKeyCalled, isTrue);

    // Emergency entries should survive
    final remaining = await db.syncQueueDao.pendingEntries();
    final emergencyEntries = remaining.where((e) => e.isEmergency).toList();
    expect(emergencyEntries, hasLength(2));
    expect(emergencyEntries.every((e) => e.isEmergency), isTrue);
  });

  test('normal queue entries are discarded on force logout, emergency kept', () async {
    await db.syncQueueDao.insertEntry(
      queueTable: 'schools',
      recordLocalId: 1,
      operation: 'INSERT',
      payload: {'local_id': 1, 'data': {'schoolName': 'Normal School'}},
      isEmergency: false,
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'schools',
      recordLocalId: 2,
      operation: 'INSERT',
      payload: {'local_id': 2, 'data': {'schoolName': 'Emergency School'}},
      isEmergency: true,
    );

    final allEntries = await db.syncQueueDao.pendingEntries();
    expect(allEntries, hasLength(2));

    // Both entries fail push so both remain in queue before purge
    final remote = FakeSyncRemoteApi(
      pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
      pushResponses: [
        SyncPushResponse(
          results: [
            SyncPushResult(
              localId: 1,
              status: 'error',
              serverId: null,
              retryable: false,
            ),
            SyncPushResult(
              localId: 2,
              status: 'error',
              serverId: null,
              retryable: false,
            ),
          ],
        ),
      ],
      realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
    );

    final security = TrackingSecurityService();
    final service = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: security,
      remoteApi: remote,
      store: store,
      mergeEngine: MergeEngine(),
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
      accountActive: false,
    );

    await service.onConnectivityRestored();
    await security.clearSessionKey();

    // _applyCreditState() purges isEmergency==false entries.
    // The normal entry (id=1) failed push so it would have remained,
    // but the purge deletes it. The emergency entry (id=2) also failed
    // push and survives the purge because isEmergency==true.
    final remaining = await db.syncQueueDao.pendingEntries();
    expect(remaining, hasLength(1));
    expect(remaining.first.isEmergency, isTrue);
    expect(remaining.first.recordLocalId, 2);
  });

  test('emergency entries sorted before normal entries', () async {
    // Insert in reverse priority order
    await db.syncQueueDao.insertEntry(
      queueTable: 'lessons',
      recordLocalId: 3,
      operation: 'UPDATE',
      payload: {},
      isEmergency: false,
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'schools',
      recordLocalId: 1,
      operation: 'INSERT',
      payload: {},
      isEmergency: true,
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'subjects',
      recordLocalId: 2,
      operation: 'INSERT',
      payload: {},
      isEmergency: false,
    );

    final pending = await db.syncQueueDao.pendingEntries();
    expect(pending, hasLength(3));

    // First entry should be emergency (sorted first by isEmergency DESC)
    expect(pending.first.isEmergency, isTrue);
    expect(pending.first.queueTable, 'schools');
  });

  test('emergency queue survives multiple sync attempts', () async {
    await db.syncQueueDao.insertEntry(
      queueTable: 'schools',
      recordLocalId: 1,
      operation: 'INSERT',
      payload: {'local_id': 1, 'data': {'schoolName': 'Emergency'}},
      isEmergency: true,
    );

    // First sync attempt - fails
    final remote1 = FakeSyncRemoteApi(
      pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
      pushResponses: [
        SyncPushResponse(
          results: [
            SyncPushResult(
              localId: 1,
              status: 'error',
              serverId: null,
              retryable: true,
            ),
          ],
        ),
      ],
      realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
    );

    final security = TrackingSecurityService();
    final service1 = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: security,
      remoteApi: remote1,
      store: store,
      mergeEngine: MergeEngine(),
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
    );

    await service1.onConnectivityRestored();

    // Entry should still be there (with incremented attempts)
    var pending = await db.syncQueueDao.pendingEntries();
    expect(pending, hasLength(1));
    expect(pending.first.attempts, greaterThan(0));

    // Force logout
    await security.clearSessionKey();

    // Emergency entry still survives
    pending = await db.syncQueueDao.pendingEntries();
    expect(pending, hasLength(1));
    expect(pending.first.isEmergency, isTrue);
  });
}
