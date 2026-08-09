import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:drift/drift.dart';
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

    await db.into(db.lessons).insert(
      LessonsCompanion.insert(
        id: const Value(10),
        serverId: const Value('srv-lesson-10'),
        subject: 'Mathematics',
        classLevel: 'SS1',
        week: 1,
        topic: 'Local lesson',
        difficulty: 'medium',
        bloomsVerbs: '[]',
        curriculum: 'nerdc',
        content: '',
        updateCounter: const Value(1),
        isDeleted: const Value(false),
        status: const Value('draft'),
        isUnlocked: const Value(true),
      ),
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
                'server_id': 'srv-lesson-10',
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
    // Topological order: schools → subjects → exams. security_config is no longer client-pushed.
    expect(
      remote.pushCalls.first.map((batch) => batch.table).toList(),
      ['schools', 'subjects', 'exams'],
    );
    expect(store.syncedRecords['lessons']?[10]?['title'], 'Remote lesson');
    final pending = await db.syncQueueDao.pendingEntries();
    expect(pending, isEmpty);
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
    final pending = await db.syncQueueDao.pendingEntries();
    final emergency = pending.where((e) => e.isEmergency).toList();
    expect(emergency, hasLength(1));
    expect(emergency.first.queueTable, 'schools');
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

  test(
    'flushes deferred teachers on the next normal pull once the school exists locally',
    () async {
      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'teachers',
                row: {
                  'id': 'teacher-1',
                  'email': 'teacher@example.com',
                  'teacher_name': 'Teacher One',
                  'role': 'teacher',
                  'school_id': 'school-1',
                  'is_active': true,
                  'force_password_reset': true,
                  'password_hash_version': 1,
                  'created_at': '2026-08-09T08:00:00.000Z',
                  'updated_at': '2026-08-09T08:00:00.000Z',
                },
              ),
            ],
            nextCursor: null,
          ),
          const SyncPullPage(changes: [], nextCursor: null),
        ],
        pushResponses: [const SyncPushResponse(results: [])],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
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

      final deferredAfterFirstPull = await db.select(db.syncQueueSnapshot).get();
      expect(deferredAfterFirstPull, hasLength(1));
      expect(
        await (db.select(db.teachers)
              ..where((t) => t.serverId.equals('teacher-1')))
            .get(),
        isEmpty,
      );

      await db.into(db.schools).insert(
            SchoolsCompanion.insert(
              serverId: const Value('school-1'),
              schoolName: 'Test School',
              shortCode: 'TS1',
            ),
          );

      await service.onConnectivityRestored();

      final teachers = await (db.select(db.teachers)
            ..where((t) => t.serverId.equals('teacher-1')))
          .get();
      final deferredAfterSecondPull = await db.select(db.syncQueueSnapshot).get();

      expect(teachers, hasLength(1));
      expect(teachers.first.email, 'teacher@example.com');
      expect(deferredAfterSecondPull, isEmpty);
    },
  );
}
