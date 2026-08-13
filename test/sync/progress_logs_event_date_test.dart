// Regression tests for the progress_logs event_date data-integrity defect:
//   1. Already-queued INSERT payloads that lack event_date are healed at push
//      time by injecting the local row's actual eventDate — without any
//      server schema change.
//   2. New-style payloads that already include event_date pass through
//      unchanged (the self-heal never clobbers an explicit value).
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

Future<void> _seedConfig(AppDatabase db) async {
  // Direct insert to bypass updateConfig() which auto-creates sync queue entries
  await db.into(db.securityConfig).insert(
    SecurityConfigCompanion.insert(
      currentDeviceId: 'test-device-001',
      lastRealtimeEventId: Value(0),
    ),
  );
}

SyncService _makeService(
  AppDatabase db,
  FakeSyncRecordStore store,
  FakeSyncRemoteApi remote,
) {
  return SyncService(
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

  test(
    'queued progress_logs INSERT without event_date is healed at push time '
    'using the local row\'s eventDate',
    () async {
      final eventDate = DateTime.utc(2026, 8, 1, 10, 30, 0);
      final logId = await db.into(db.progressLogs).insert(
            ProgressLogsCompanion.insert(
              eventType: 'lesson_completed',
              lessonId: const Value(1),
              teacherId: const Value(1),
              schoolId: const Value(1),
              eventDate: Value(eventDate),
            ),
          );

      // Old-style queue entry: the payload has no event_date (the defect).
      await db.syncQueueDao.insertEntry(
        queueTable: 'progress_logs',
        recordLocalId: logId,
        operation: 'INSERT',
        payload: {
          'event_type': 'lesson_completed',
          'lesson_id': 1,
          'teacher_id': 'teacher-1',
          'school_id': 'school-1',
        },
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      expect(remote.pushCalls, hasLength(1));
      final batch = remote.pushCalls.first.single;
      expect(batch.table, 'progress_logs');
      expect(batch.operation, 'INSERT');
      // 'event_date' is not in the compression key map, so it is sent as-is.
      expect(
        batch.record['event_date'],
        eventDate.toUtc().toIso8601String(),
        reason: 'payload must carry the local row\'s actual eventDate',
      );

      // The healed entry succeeded (default fake response is 'updated')
      // and was removed from the queue.
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );

  test(
    'new progress_logs payload that already includes event_date is pushed '
    'unchanged',
    () async {
      final payloadDate = DateTime.utc(2026, 8, 2, 9, 0, 0);
      final localRowDate = DateTime.utc(2026, 8, 2, 9, 0, 1);
      final logId = await db.into(db.progressLogs).insert(
            ProgressLogsCompanion.insert(
              eventType: 'lesson_completed',
              lessonId: const Value(1),
              teacherId: const Value(1),
              schoolId: const Value(1),
              eventDate: Value(localRowDate),
            ),
          );

      // New-style payload (the shape produced by the lesson editor enqueue
      // sites after the fix).
      await db.syncQueueDao.insertEntry(
        queueTable: 'progress_logs',
        recordLocalId: logId,
        operation: 'INSERT',
        payload: {
          'event_type': 'lesson_completed',
          'event_date': payloadDate.toUtc().toIso8601String(),
          'lesson_id': 1,
          'teacher_id': 'teacher-1',
          'school_id': 'school-1',
        },
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final batch = remote.pushCalls.first.single;
      expect(
        batch.record['event_date'],
        payloadDate.toUtc().toIso8601String(),
        reason: 'an explicit payload event_date must be preserved, '
            'not replaced by the local row value',
      );
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );
}
