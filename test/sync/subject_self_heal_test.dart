// Regression tests for the permanent missing-subject self-heal:
//   1. Local subject with a wrong non-null server_id and no matching active
//      server subject → stale server_id cleared, clean INSERT queued, the
//      next push batch contains the subject, and a second cycle is a no-op.
//   2. Local subject with null server_id and an active matching server
//      subject → adopts the correct server id, no INSERT queued.
//   3. Soft-deleted / inactive server subject with a matching name → no
//      INSERT queued, local row left unchanged.
//   4. Pending subjects INSERT already exists → no duplicate queue entry.
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

Map<String, dynamic> _serverSubject(
  String id,
  String name, {
  bool active = true,
  String? deletedAt,
}) {
  return {
    'id': id,
    'subject_name': name,
    'school_id': 'school-1',
    'is_active': active,
    'deleted_at': deletedAt,
  };
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
    'subject with wrong non-null server_id and no active server match is '
    'healed: server_id cleared, INSERT queued, next push contains it, '
    'second cycle is a no-op',
    () async {
      // Local subject carrying a WRONG server_id — the old cross-table
      // local_id collision outcome (the UUID actually belongs to a lesson).
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(1),
              name: 'English Studies',
              schoolId: const Value('school-1'),
              serverId: const Value('00000000-0000-0000-0000-000000000001'),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          // Cycle 1: the server catalog lacks the subject.
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            subjectCatalog: [
              _serverSubject('srv-math', 'Mathematics'),
            ],
          ),
          // Cycle 2: the subject now exists server-side (after the INSERT).
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            subjectCatalog: [
              _serverSubject('srv-math', 'Mathematics'),
              _serverSubject('srv-english', 'English Studies'),
            ],
          ),
        ],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 1,
                status: 'created',
                serverId: 'srv-english',
                retryable: false,
              ),
            ],
          ),
        ],
        realtimePages: [
          const SyncRealtimePage(events: [], latestEventId: 0),
          const SyncRealtimePage(events: [], latestEventId: 0),
        ],
      );

      final service = _makeService(db, store, remote);

      // Cycle 1: reconcile clears the stale server_id and queues the INSERT.
      await service.onConnectivityRestored();

      var subject = await (db.select(db.subjects)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(subject.serverId, isNull,
          reason: 'stale server_id must be cleared');

      var pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1));
      expect(pending.first.queueTable, 'subjects');
      expect(pending.first.operation, 'INSERT');

      // Cycle 2: the queued INSERT is pushed ('created' with srv-english),
      // the pull now shows the subject, and reconciliation is a no-op.
      await service.onConnectivityRestored();

      subject = await (db.select(db.subjects)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(subject.serverId, 'srv-english');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'no re-queue after healing');

      // The push batch that created the subject carried the clean payload.
      expect(remote.pushCalls, hasLength(1));
      final batch = remote.pushCalls.first.single;
      expect(batch.table, 'subjects');
      expect(batch.operation, 'INSERT');
      // 'name' compresses to 'n'; 'school_id' passes through unchanged.
      expect(batch.record['n'], 'English Studies');
      expect(batch.record['school_id'], 'school-1');
    },
  );

  test(
    'subject with null server_id and an active matching server subject '
    'adopts the correct server id without queueing an INSERT',
    () async {
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(1),
              name: 'English Studies',
              schoolId: const Value('school-1'),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            subjectCatalog: [
              _serverSubject('srv-english', 'English Studies'),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final subject = await (db.select(db.subjects)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(subject.serverId, 'srv-english',
          reason: 'local row must adopt the server subject id');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'no INSERT queued for a subject the server already has');
    },
  );

  test(
    'soft-deleted or inactive server subject with a matching name never '
    'triggers an INSERT and leaves the local row unchanged',
    () async {
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(1),
              name: 'Basic Science',
              schoolId: const Value('school-1'),
              serverId: const Value('srv-basic'),
            ),
          );
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(2),
              name: 'Igbo',
              schoolId: const Value('school-1'),
              serverId: const Value('srv-igbo'),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            subjectCatalog: [
              // Soft-deleted row.
              _serverSubject('srv-basic', 'Basic Science',
                  deletedAt: '2026-08-01T00:00:00Z'),
              // Inactive row.
              _serverSubject('srv-igbo', 'Igbo', active: false),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final basic = await (db.select(db.subjects)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      final igbo = await (db.select(db.subjects)
            ..where((t) => t.id.equals(2)))
          .getSingle();
      expect(basic.serverId, 'srv-basic',
          reason: 'local row must be untouched');
      expect(igbo.serverId, 'srv-igbo',
          reason: 'local row must be untouched');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'soft-deleted/inactive subjects must never be re-pushed');
    },
  );

  test(
    'pending subjects INSERT already exists — no duplicate queue entry is added',
    () async {
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(1),
              name: 'English Studies',
              schoolId: const Value('school-1'),
            ),
          );
      await db.syncQueueDao.insertEntry(
        queueTable: 'subjects',
        recordLocalId: 1,
        operation: 'INSERT',
        payload: {'name': 'English Studies', 'school_id': 'school-1'},
      );

      // The push fails (retryable) so the entry stays pending when the
      // reconciliation runs — exactly the state the guard must handle.
      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            subjectCatalog: [
              _serverSubject('srv-math', 'Mathematics'),
            ],
          ),
        ],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 1,
                status: 'error',
                serverId: null,
                retryable: true,
                errorMessage: 'transient failure',
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Reconcile sees the subject is missing server-side but an INSERT is
      // already pending → no duplicate entry.
      var pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1));
      expect(pending.first.queueTable, 'subjects');

      // A second cycle (the entry is in cooldown, so it is not pushed) still
      // adds nothing.
      await service.onConnectivityRestored();
      pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1),
          reason: 'must stay a single pending entry across cycles');
    },
  );
}
