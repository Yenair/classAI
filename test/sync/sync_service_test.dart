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

  test('pulls first, then merges, then pushes in topological order', () async {
    await db.syncQueueDao.insertEntry(
      queueTable: 'exams',
      recordLocalId: 3,
      operation: 'UPDATE',
      payload: {'local_id': 3, 'data': {'title': 'Exam 3'}},
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'schools',
      recordLocalId: 1,
      operation: 'INSERT',
      payload: {'local_id': 1, 'data': {'schoolName': 'School'}},
      isEmergency: true,
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'subjects',
      recordLocalId: 2,
      operation: 'INSERT',
      payload: {'local_id': 2, 'data': {'name': 'Math'}},
    );

    store.seedLocalRecord('lessons', 10, {
      'localId': 10,
      'title': 'Local lesson',
      'updateCounter': 1,
    });
    store.seedBaseRecord(
      tableName: 'lessons',
      localId: 10,
      record: {
        'localId': 10,
        'title': 'Base lesson',
        'updateCounter': 0,
      },
    );
    await store.seedVersionHashRow(tableName: 'lessons', localId: 10);

    final remote = FakeSyncRemoteApi(
      pullPages: [
        SyncPullPage(
          changes: [
            SyncChange(
              table: 'lessons',
              row: {
                'localId': 10,
                'title': 'Remote lesson',
                'updateCounter': 2,
              },
            ),
          ],
          nextCursor: null,
        ),
      ],
      pushResponses: [
        SyncPushResponse(
          results: [
            SyncPushResult(localId: 1, status: 'created', serverId: 'srv-1', retryable: false),
            SyncPushResult(localId: 2, status: 'created', serverId: 'srv-2', retryable: false),
            SyncPushResult(localId: 3, status: 'updated', serverId: 'srv-3', retryable: false),
          ],
        ),
      ],
      realtimePages: [
        const SyncRealtimePage(events: [], latestEventId: 0),
      ],
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
    );

    await service.onConnectivityRestored();

    expect(remote.pullCalls, isNotEmpty);
    expect(remote.pushCalls, isNotEmpty);
    expect(
      remote.pushCalls.first.map((batch) => batch.table).toList(),
      ['schools', 'subjects', 'exams'],
    );
    expect(store.syncedRecords['lessons']?[10]?['title'], 'Remote lesson');
    expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    expect(service.state, SyncState.idle);
  });

  test('preserves emergency queue when account is deactivated', () async {
    await db.syncQueueDao.insertEntry(
      queueTable: 'schools',
      recordLocalId: 1,
      operation: 'INSERT',
      payload: {'local_id': 1, 'data': {'schoolName': 'School'}},
      isEmergency: true,
    );

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
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
      accountActive: false,
    );

    await service.onConnectivityRestored();

    expect(security.clearSessionKeyCalled, isTrue);
    expect(await db.syncQueueDao.pendingEntries(), hasLength(1));
    expect(service.state, SyncState.idle);
  });

  test('deduplicates realtime by event id, not timestamp', () async {
    await db.securityConfigDao.updateConfig(lastRealtimeEventId: 4);

    final remote = FakeSyncRemoteApi(
      pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
      pushResponses: [const SyncPushResponse(results: [])],
      realtimePages: [
        SyncRealtimePage(
          events: [
            SyncRealtimeEvent(
              eventId: 5,
              table: 'lessons',
              payload: {'localId': 11, 'title': 'Realtime 5'},
            ),
            SyncRealtimeEvent(
              eventId: 3,
              table: 'lessons',
              payload: {'localId': 12, 'title': 'Realtime 3'},
            ),
          ],
          latestEventId: 5,
        ),
      ],
    );

    final service = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: TrackingSecurityService(),
      remoteApi: remote,
      store: store,
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
    );

    await service.onConnectivityRestored();

    expect(store.syncedRecords['lessons']?.keys, contains(11));
    expect(store.syncedRecords['lessons']?.keys, isNot(contains(12)));
    final config = await db.securityConfigDao.get();
    expect(config.lastRealtimeEventId, 5);
  });
}
