// Tests for the permanent fix for UPDATE/DELETE sync queue entries whose
// local row has no server_id (they retry forever — the production case:
// lessons localId=62, attempts=8, retryable=true, server rejects with
// "missing server_id").
//
//   1. UPDATE with no server_id and no pending INSERT → converted to a clean
//      INSERT (the same payload builder the full-table reconciliation uses)
//      and pushed; server_id adopted on success.
//   2. UPDATE with no server_id superseded by a pending INSERT for the same
//      row → marked terminal ("UPDATE superseded by pending INSERT"); the
//      INSERT owns the server row.
//   3. DELETE with no server_id → marked terminal ("nothing to delete
//      server-side") and never pushed.
//   4. UPDATE that can resolve a server_id → existing behavior unchanged.
//   5. UPDATE with no server_id whose clean INSERT payload cannot be built →
//      left unchanged (still pushed as UPDATE, still retryable).
//   6. scheme_of_work UPDATE with no server_id → converted to INSERT with
//      FK resolution from the local teacher/subject rows.
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
    SecurityConfigCompanion.insert(
      currentDeviceId: 'test-device-001',
      lastRealtimeEventId: Value(0),
    ),
  );
}

Future<void> _seedSchool(AppDatabase db, {int localId = 1}) async {
  await db.into(db.schools).insert(
    SchoolsCompanion.insert(
      localId: Value(localId),
      serverId: const Value('school-1'),
      schoolName: 'Test School',
      shortCode: 'TS1',
    ),
  );
}

Future<void> _seedTeacher(
  AppDatabase db, {
  int localId = 1,
  String serverId = 'teacher-1',
  int schoolLocalId = 1,
}) async {
  await db.into(db.teachers).insert(
    TeachersCompanion.insert(
      localId: Value(localId),
      serverId: Value(serverId),
      email: 'teacher-$localId@example.com',
      teacherName: 'Teacher $localId',
      schoolLocalId: schoolLocalId,
      schoolServerId: const Value('school-1'),
    ),
  );
}

Future<void> _seedSubject(
  AppDatabase db, {
  required int id,
  required String name,
  String? serverId,
  String? schoolId = 'school-1',
}) async {
  await db.into(db.subjects).insert(
    SubjectsCompanion.insert(
      id: Value(id),
      name: name,
      serverId: serverId != null ? Value(serverId) : const Value.absent(),
      schoolId: schoolId != null ? Value(schoolId) : const Value.absent(),
    ),
  );
}

Future<void> _seedLesson(
  AppDatabase db, {
  required int id,
  String? serverId,
  String? schoolServerId = 'school-1',
  String teacherServerId = 'teacher-1',
  String subject = 'Mathematics',
  String classLevel = 'JSS 1',
  int week = 1,
  String? term = 'first',
  String topic = 'Fractions',
}) async {
  await db.into(db.lessons).insert(
    LessonsCompanion.insert(
      id: Value(id),
      serverId: serverId != null ? Value(serverId) : const Value.absent(),
      subject: subject,
      classLevel: classLevel,
      week: week,
      topic: topic,
      difficulty: 'medium',
      bloomsVerbs: 'list',
      curriculum: 'NERDC',
      content: '{"enc": true}',
      teacherServerId: Value(teacherServerId),
      schoolServerId: schoolServerId != null
          ? Value(schoolServerId)
          : const Value.absent(),
      status: const Value('draft'),
      term: term != null ? Value(term) : const Value.absent(),
    ),
  );
}

// The DAO-crafted lesson payload used by the editor queue sites — never
// carries server_id.
Map<String, dynamic> _lessonUpdatePayload() => {
      'subject': 'Mathematics',
      'class_level': 'JSS 1',
      'week': 1,
      'topic': 'Fractions',
      'difficulty': 'medium',
      'blooms_verbs': 'list',
      'curriculum': 'NERDC',
      'teacher_server_id': 'teacher-1',
      'school_server_id': 'school-1',
      'content': '{"enc": true}',
      'is_unlocked': false,
      'status': 'submitted',
      'week_number': 1,
      'term': 'first',
    };

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
    'UPDATE with no server_id and no pending INSERT is converted to a clean '
    'INSERT and pushed',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      // The production shape: local lesson never got a server_id.
      await _seedLesson(db, id: 62, serverId: null);
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 62,
        operation: 'UPDATE',
        payload: _lessonUpdatePayload(),
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 62,
                status: 'created',
                serverId: 'srv-62',
                retryable: false,
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Pushed once, as an INSERT, with the clean reconciliation payload.
      expect(remote.pushCalls, hasLength(1));
      final batch = remote.pushCalls.first.single;
      expect(batch.table, 'lessons');
      expect(batch.operation, 'INSERT');
      expect(batch.record['lid'], 62);
      expect(batch.record['s'], 'Mathematics');
      expect(batch.record['tsid'], 'teacher-1');
      expect(batch.record['ssid'], 'school-1');
      expect(batch.record['w'], 1);
      expect(batch.record['sid'], isNull,
          reason: 'no server_id — the server generates it on INSERT');

      // Server_id adopted locally, entry removed.
      final lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(62)))
          .getSingle();
      expect(lesson.serverId, 'srv-62');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );

  test(
    'UPDATE with no server_id superseded by a pending INSERT is marked '
    'terminal',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      await _seedLesson(db, id: 62, serverId: null);
      // The pending INSERT will create the server row.
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 62,
        operation: 'INSERT',
        payload: _lessonUpdatePayload(),
      );
      // The stuck UPDATE for the same local row.
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 62,
        operation: 'UPDATE',
        payload: {'status': 'submitted'},
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 62,
                status: 'created',
                serverId: 'srv-62',
                retryable: false,
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Only the INSERT reached the server.
      expect(remote.pushCalls, hasLength(1));
      expect(remote.pushCalls.first, hasLength(1));
      expect(remote.pushCalls.first.single.operation, 'INSERT');

      // The INSERT's server_id was adopted and the UPDATE is terminal with
      // the superseded error.
      final lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(62)))
          .getSingle();
      expect(lesson.serverId, 'srv-62');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
      final terminal = await db.syncQueueDao.terminalEntries();
      expect(terminal, hasLength(1));
      expect(terminal.single.operation, 'UPDATE');
      expect(terminal.single.lastError,
          contains('UPDATE superseded by pending INSERT'));
    },
  );

  test(
    'DELETE with no server_id is marked terminal and never pushed',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      await _seedLesson(db, id: 62, serverId: null);
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 62,
        operation: 'DELETE',
        payload: {'server_id': null, 'local_id': 62},
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      expect(remote.pushCalls, isEmpty,
          reason: 'a DELETE with no server row must never reach the server');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
      final terminal = await db.syncQueueDao.terminalEntries();
      expect(terminal, hasLength(1));
      expect(terminal.single.operation, 'DELETE');
      expect(terminal.single.lastError,
          contains('nothing to delete server-side'));
    },
  );

  test(
    'UPDATE that can resolve a server_id keeps existing behavior',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      // Local row HAS a server_id — the entry must stay an UPDATE.
      await _seedLesson(db, id: 62, serverId: 'srv-62');
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 62,
        operation: 'UPDATE',
        payload: {'subject': 'Mathematics', 'status': 'submitted'},
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 62,
                status: 'updated',
                serverId: 'srv-62',
                retryable: false,
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final batch = remote.pushCalls.first.single;
      expect(batch.operation, 'UPDATE',
          reason: 'an entry whose local row has a server_id must stay UPDATE');
      expect(batch.record['sid'], 'srv-62',
          reason: 'server_id injected from the local row');
      expect(batch.record['lid'], 62);
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );

  test(
    'UPDATE with no server_id and no buildable INSERT payload keeps current '
    'behavior',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      // teacherServerId is empty → the lesson INSERT builder cannot resolve
      // the teacher FK, so no clean INSERT payload can be built.
      await _seedLesson(
        db,
        id: 62,
        serverId: null,
        teacherServerId: '',
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 62,
        operation: 'UPDATE',
        payload: {'status': 'submitted'},
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 62,
                status: 'error',
                serverId: null,
                retryable: true,
                errorMessage: 'UPDATE on "lessons" missing server_id',
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Still an UPDATE, still pushed, still retryable — untouched.
      expect(remote.pushCalls.first.single.operation, 'UPDATE');
      final pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1));
      expect(pending.single.operation, 'UPDATE');
      expect(pending.single.attempts, 1);
    },
  );

  test(
    'scheme_of_work UPDATE with no server_id converts to INSERT with FK '
    'resolution',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db, localId: 1, serverId: 'teacher-1');
      await _seedSubject(
        db,
        id: 1,
        name: 'Mathematics',
        serverId: 'subject-1',
      );
      await db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          id: const Value(1),
          serverId: const Value(null),
          schoolId: const Value(1),
          teacherId: const Value(1),
          subjectId: const Value(1),
          term: const Value('first'),
          weekNumber: const Value(3),
          topic: const Value('Fractions'),
          status: const Value('draft'),
          classLevel: const Value('JSS 1'),
        ),
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: 1,
        operation: 'UPDATE',
        payload: {'status': 'submitted'},
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 1,
                status: 'created',
                serverId: 'srv-sow-1',
                retryable: false,
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final batch = remote.pushCalls.first.single;
      expect(batch.table, 'scheme_of_work');
      expect(batch.operation, 'INSERT');
      expect(batch.record['lid'], 1);
      // FKs resolve from the local teacher/subject rows + the school id.
      expect(batch.record['tsid'], 'teacher-1');
      expect(batch.record['ssid'], 'school-1');
      expect(batch.record['subid'], 'subject-1');

      final sow = await (db.select(db.schemeOfWork)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(sow.serverId, 'srv-sow-1');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );
}
