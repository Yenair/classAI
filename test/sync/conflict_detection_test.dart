import 'package:drift/drift.dart' hide isNotNull;
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

  test('conflict saved when both local and remote change same field', () async {
    // Seed local record
    store.seedLocalRecord('lessons', 10, {
      'localId': 10,
      'title': 'Local title',
      'content': 'Local body',
      'updateCounter': 2,
    });
    // Seed base (common ancestor)
    store.seedBaseRecord(
      tableName: 'lessons',
      localId: 10,
      record: {
        'localId': 10,
        'title': 'Base title',
        'content': 'Base body',
        'updateCounter': 1,
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
                'title': 'Remote title',
                'content': 'Remote body',
                'updateCounter': 2,
              },
            ),
          ],
          nextCursor: null,
        ),
      ],
      pushResponses: [
        const SyncPushResponse(results: []),
      ],
      realtimePages: [
        const SyncRealtimePage(events: [], latestEventId: 0),
      ],
    );

    final service = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: TrackingSecurityService(),
      remoteApi: remote,
      store: store,
      mergeEngine: MergeEngine(),
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
    );

    await service.onConnectivityRestored();

    // Both local and remote changed 'title' and 'content' from base with same updateCounter
    // so both fields should be conflicts (resolution.unresolved)
    expect(store.savedConflicts, isNotEmpty);
    final conflict = store.savedConflicts.first;
    expect(conflict['recordType'], 'lessons');
    expect(conflict['recordLocalId'], 10);
    expect(conflict['conflictingFields'], isNotEmpty);
    expect(conflict['resolution'], MergeResolution.unresolved.name);
  });

  test('no conflict when local and remote change different fields', () async {
    store.seedLocalRecord('lessons', 20, {
      'localId': 20,
      'title': 'Local updated title',
      'content': 'Base body',
      'updateCounter': 2,
    });
    store.seedBaseRecord(
      tableName: 'lessons',
      localId: 20,
      record: {
        'localId': 20,
        'title': 'Base title',
        'content': 'Base body',
        'updateCounter': 1,
      },
    );
    await store.seedVersionHashRow(tableName: 'lessons', localId: 20);

    final remote = FakeSyncRemoteApi(
      pullPages: [
        SyncPullPage(
          changes: [
            SyncChange(
              table: 'lessons',
              row: {
                'localId': 20,
                'title': 'Base title',
                'content': 'Remote body',
                'updateCounter': 2,
              },
            ),
          ],
          nextCursor: null,
        ),
      ],
      pushResponses: [
        const SyncPushResponse(results: []),
      ],
      realtimePages: [
        const SyncRealtimePage(events: [], latestEventId: 0),
      ],
    );

    final service = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: TrackingSecurityService(),
      remoteApi: remote,
      store: store,
      mergeEngine: MergeEngine(),
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
    );

    await service.onConnectivityRestored();

    // local changed 'title', remote changed 'content' — different fields, no conflict
    expect(store.savedConflicts, isEmpty);
  });

  test('merge applies union strategy for JSON array fields', () async {
    store.seedLocalRecord('lessons', 30, {
      'localId': 30,
      'objectives': ['Obj A', 'Obj B'],
      'updateCounter': 1,
    });
    store.seedBaseRecord(
      tableName: 'lessons',
      localId: 30,
      record: {
        'localId': 30,
        'objectives': ['Obj A'],
        'updateCounter': 0,
      },
    );
    await store.seedVersionHashRow(tableName: 'lessons', localId: 30);

    final remote = FakeSyncRemoteApi(
      pullPages: [
        SyncPullPage(
          changes: [
            SyncChange(
              table: 'lessons',
              row: {
                'localId': 30,
                'objectives': ['Obj B', 'Obj C'],
                'updateCounter': 2,
              },
            ),
          ],
          nextCursor: null,
        ),
      ],
      pushResponses: [
        const SyncPushResponse(results: []),
      ],
      realtimePages: [
        const SyncRealtimePage(events: [], latestEventId: 0),
      ],
    );

    final service = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: TrackingSecurityService(),
      remoteApi: remote,
      store: store,
      mergeEngine: MergeEngine(),
      isForeground: false,
      sessionKeyValid: true,
      biometricAvailable: false,
    );

    await service.onConnectivityRestored();

    // objectives uses union strategy — should merge all unique values
    final merged = store.syncedRecords['lessons']?[30];
    expect(merged, isNotNull);
    final objectives = merged!['objectives'] as List;
    expect(objectives, containsAll(['Obj A', 'Obj B', 'Obj C']));
    // Verify no conflict was saved for union fields
    final conflictsForRecord = store.savedConflicts
        .where((c) => c['recordLocalId'] == 30 && c['recordType'] == 'lessons');
    expect(conflictsForRecord, isEmpty);
  });

  test('conflicts saved to database and retrievable', () async {
    // Directly test the db conflict table
    final now = DateTime.now();
    await db.into(db.conflicts).insert(
          ConflictsCompanion.insert(
            recordType: 'exams',
            recordLocalId: 1,
            conflictingFields: '["markingScheme","title"]',
            resolution: Value('unresolved'),
            notified: Value(false),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );

    final conflicts = await db.select(db.conflicts).get();
    expect(conflicts, hasLength(1));
    expect(conflicts.first.recordType, 'exams');
    expect(conflicts.first.recordLocalId, 1);
    expect(conflicts.first.resolution, 'unresolved');

    // Resolve the conflict
    await (db.update(db.conflicts)..where((t) => t.id.equals(conflicts.first.id)))
        .write(
          ConflictsCompanion(
            resolution: Value('resolved'),
            notified: Value(true),
          ),
        );

    final resolved = await db.select(db.conflicts).get();
    expect(resolved.first.resolution, 'resolved');
    expect(resolved.first.notified, true);
  });
}
