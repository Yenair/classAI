// Tests for the generalized full-table sync reconciliation
// (plans/sync_full_table_reconciliation.md):
//   lessons/exams/scheme_of_work/progress_logs reconciled against the
//   server-provided identity catalogs each pull, with:
//     Fix 1  progress_logs one-shot re-queue (never twice)
//     Fix 2  ambiguous natural key -> flag, never adopt
//     Fix 3  safe Tier 2 adoption (fill when null; adopt-with-reason only when
//            the existing server_id is provably absent from the catalog)
//     Fix 4  strict school scoping (null/other-school rows -> unscoped)
//     Fix 6  stop-limit (3 cycles for lessons/exams/SoW, then manual review)
//     Fix 7  debugDumpReconcileIssues surfaces over-threshold rows + counts
import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:classai/core/utils/payload_compressor.dart';
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
  bool isDeleted = false,
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
      isDeleted: Value(isDeleted),
    ),
  );
}

Map<String, dynamic> _lessonCatalogRow({
  required String id,
  String teacherId = 'teacher-1',
  String subjectId = 'subject-1',
  String classLevel = 'JSS 1',
  int week = 1,
  String? term = 'first',
  String topic = 'Fractions',
  bool deleted = false,
  String? deletedAt,
}) {
  return {
    'id': id,
    'school_id': 'school-1',
    'teacher_id': teacherId,
    'subject_id': subjectId,
    'subject': 'Mathematics',
    'class_level': classLevel,
    'week': week,
    'week_number': week,
    'term': term,
    'topic': topic,
    'is_deleted': deleted,
    'deleted_at': deletedAt,
    'updated_at': '2026-08-13T00:00:00Z',
  };
}

Map<String, dynamic> _sowCatalogRow({
  required String id,
  String subjectId = 'subject-1',
  String term = 'first',
  int weekNumber = 3,
  bool deleted = false,
}) {
  return {
    'id': id,
    'school_id': 'school-1',
    'teacher_id': 'teacher-1',
    'subject_id': subjectId,
    'term': term,
    'week_number': weekNumber,
    'topic': 'Fractions',
    'class_level': 'JSS 1',
    'status': 'draft',
    'is_deleted': deleted,
    'deleted_at': null,
    'updated_at': '2026-08-13T00:00:00Z',
  };
}

Map<String, dynamic> _progressCatalogRow({
  required String id,
  String teacherId = 'teacher-1',
  String eventType = 'lesson_completed',
  required String eventDate,
  bool deleted = false,
}) {
  return {
    'id': id,
    'school_id': 'school-1',
    'teacher_id': teacherId,
    'lesson_id': null,
    'exam_id': null,
    'event_type': eventType,
    'event_date': eventDate,
    'notes': null,
    'is_deleted': deleted,
    'deleted_at': null,
    'updated_at': '2026-08-13T00:00:00Z',
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

SyncPullPage _page(
  Map<String, List<Map<String, dynamic>>> catalogs, {
  List<Map<String, dynamic>>? subjectCatalog,
}) {
  return SyncPullPage(
    changes: const [],
    nextCursor: null,
    tableCatalogs: catalogs,
    subjectCatalog: subjectCatalog,
  );
}

SyncPushResponse _terminalFailure(int localId) {
  return SyncPushResponse(
    results: [
      SyncPushResult(
        localId: localId,
        status: 'error',
        serverId: null,
        retryable: false,
        errorMessage: 'permanent rejection',
      ),
    ],
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
    'lesson missing server-side with a stale server_id is healed: cleared, '
    'INSERT queued, pushed next cycle, second cycle is a no-op and the '
    'reconcile-state is cleared',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await _seedLesson(
        db,
        id: 1,
        serverId: '00000000-0000-0000-0000-000000000099',
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          // Cycle 1: catalog lacks the lesson.
          _page({
            'lessons': [
              _lessonCatalogRow(id: 'srv-w2', week: 2, topic: 'Decimals'),
            ],
          }),
          // Cycle 2: the lesson exists server-side now (after the INSERT).
          _page({
            'lessons': [
              _lessonCatalogRow(id: 'srv-w2', week: 2, topic: 'Decimals'),
              _lessonCatalogRow(id: 'lesson-srv-1', week: 1),
            ],
          }),
        ],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 1,
                status: 'created',
                serverId: 'lesson-srv-1',
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

      // Cycle 1: stale server_id cleared, clean INSERT queued.
      await service.onConnectivityRestored();
      var lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(lesson.serverId, isNull,
          reason: 'stale server_id must be cleared when missing server-side');

      var pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1));
      expect(pending.first.queueTable, 'lessons');
      expect(pending.first.operation, 'INSERT');
      expect(
        (await db.syncReconcileStateDao.getFor('lessons', 1))?.attempts,
        1,
      );

      // Cycle 2: the INSERT is pushed (created with lesson-srv-1), the pull
      // shows the row, reconciliation matches at Tier 1 and clears state.
      await service.onConnectivityRestored();
      lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(lesson.serverId, 'lesson-srv-1');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'no re-queue after healing');
      expect(await db.syncReconcileStateDao.getFor('lessons', 1), isNull,
          reason: 'tracking cleared once the row matches');

      expect(remote.pushCalls, hasLength(1));
      final batch = remote.pushCalls.first.single;
      expect(batch.table, 'lessons');
      expect(batch.operation, 'INSERT');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload['subject'], 'Mathematics');
      expect(payload['week'], 1);
      expect(payload['school_server_id'], 'school-1');
      expect(payload['teacher_server_id'], 'teacher-1');
      expect(payload['local_id'], 1);
    },
  );

  test(
    'lesson with null server_id and an active natural-key match adopts the '
    'server id without queueing an INSERT',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await _seedLesson(db, id: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({
            'lessons': [_lessonCatalogRow(id: 'lesson-srv-1')],
          }),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(lesson.serverId, 'lesson-srv-1',
          reason: 'natural-key match must be adopted');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'no INSERT for a lesson the server already has');
    },
  );

  test(
    'lesson with a server_id that is provably absent from the catalog is '
    're-bound to the natural-key match with an explicit reason (Fix 3 case 3)',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      // The stale server_id references NO row of the lessons table in this
      // school's catalog (e.g. the old cross-table collision id).
      await _seedLesson(
        db,
        id: 1,
        serverId: '99999999-9999-9999-9999-999999999999',
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({
            'lessons': [_lessonCatalogRow(id: 'lesson-srv-1')],
          }),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(lesson.serverId, 'lesson-srv-1',
          reason: 'stale (provably invalid) server_id must be adopted away');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );

  test(
    'lesson whose natural key matches two active server rows is flagged, '
    'never adopted and never re-queued (Fix 2 defensive rule)',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await _seedLesson(db, id: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({
            'lessons': [
              _lessonCatalogRow(id: 'lesson-a', topic: 'Fractions'),
              _lessonCatalogRow(id: 'lesson-b', topic: 'Decimals'),
            ],
          }),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(lesson.serverId, isNull,
          reason: 'ambiguous natural key must never be adopted');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'ambiguous natural key must never be re-queued');
    },
  );

  test(
    'lesson whose natural key exists only as a soft-deleted server row is '
    'left unchanged and never re-pushed',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await _seedLesson(db, id: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({
            'lessons': [
              _lessonCatalogRow(id: 'lesson-dead', deleted: true),
            ],
          }),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(lesson.serverId, isNull);
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'soft-deleted server rows must never be re-created');
    },
  );

  test(
    'lesson with an INSERT already pending is not queued again across cycles',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await _seedLesson(db, id: 1);
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 1,
        operation: 'INSERT',
        payload: {'subject': 'Mathematics', 'week': 1},
      );

      // The push fails retryable so the entry stays pending while the
      // reconciliation runs — exactly the state the guard must handle.
      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({'lessons': [_lessonCatalogRow(id: 'srv-w2', week: 2)]}),
          _page({'lessons': [_lessonCatalogRow(id: 'srv-w2', week: 2)]}),
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
        realtimePages: [
          const SyncRealtimePage(events: [], latestEventId: 0),
          const SyncRealtimePage(events: [], latestEventId: 0),
        ],
      );
      final service = _makeService(db, store, remote);

      await service.onConnectivityRestored();
      var pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1),
          reason: 'no duplicate INSERT while one is already pending');

      await service.onConnectivityRestored();
      pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1),
          reason: 'must stay a single pending entry across cycles');
    },
  );

  test('locally soft-deleted lessons are never re-pushed', () async {
    await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
    await _seedLesson(db, id: 1, isDeleted: true);

    final remote = FakeSyncRemoteApi(
      pullPages: [
        _page({'lessons': [_lessonCatalogRow(id: 'srv-w2', week: 2)]}),
      ],
      realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
    );
    final service = _makeService(db, store, remote);
    await service.onConnectivityRestored();

    expect(await db.syncQueueDao.pendingEntries(), isEmpty,
        reason: 'locally deleted rows must not be resurrected');
  });

  test(
    'strict school scoping: null or other-school lesson rows are unscoped and '
    'never reconciled (Fix 4)',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await _seedLesson(db, id: 1); // school-1 -> in scope, missing -> repaired
      await _seedLesson(db, id: 2, schoolServerId: 'school-2');
      await _seedLesson(db, id: 3, schoolServerId: null);

      // No matching server rows at all: only the in-scope row may be queued.
      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({
            'lessons': [
              _lessonCatalogRow(id: 'srv-w2', week: 2, topic: 'Decimals'),
            ],
          }),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1),
          reason: 'only the school-1 missing lesson is repaired');
      expect(pending.single.recordLocalId, 1);
      // Unscoped rows stay untouched.
      final other = await (db.select(db.lessons)
            ..where((t) => t.id.equals(2)))
          .getSingle();
      expect(other.serverId, isNull);
      final nullSchool = await (db.select(db.lessons)
            ..where((t) => t.id.equals(3)))
          .getSingle();
      expect(nullSchool.serverId, isNull,
          reason: 'null schoolServerId is never treated as this school');
    },
  );

  test(
    'stop-limit: after 3 missing cycles a lesson is flagged for manual review '
    'and never re-queued again; debugDumpReconcileIssues reports it (Fix 6+7)',
    () async {
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await _seedLesson(db, id: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: List.generate(
          4,
          (_) => _page({
            'lessons': [
              _lessonCatalogRow(id: 'srv-w2', week: 2, topic: 'Decimals'),
            ],
          }),
        ),
        // Each re-queued INSERT is rejected permanently so it goes terminal
        // and the next cycle tries again (this is what drives the counter).
        pushResponses: List.generate(3, (_) => _terminalFailure(1)),
        realtimePages: List.generate(
          4,
          (_) => const SyncRealtimePage(events: [], latestEventId: 0),
        ),
      );
      final service = _makeService(db, store, remote);

      await service.onConnectivityRestored(); // cycle 1: attempts -> 1
      await service.onConnectivityRestored(); // cycle 2: attempts -> 2
      await service.onConnectivityRestored(); // cycle 3: attempts -> 3
      await service.onConnectivityRestored(); // cycle 4: flagged, no re-queue

      final state = await db.syncReconcileStateDao.getFor('lessons', 1);
      expect(state, isNotNull);
      expect(state!.attempts, 3);
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'no INSERT queued after the stop-limit');
      // Only 3 pushes happened (cycles 2-4), never a 4th.
      expect(remote.pushCalls, hasLength(3));

      final lines = await service.debugDumpReconcileIssues();
      expect(
        lines.any((l) =>
            l.contains('lessons localId=1 attempts=3/3') &&
            l.contains('OVER THRESHOLD')),
        isTrue,
        reason: 'dump must surface the over-threshold row for manual review',
      );
      expect(
        lines.any((l) =>
            l.contains('lessons last-cycle counts') && l.contains('flagged')),
        isTrue,
        reason: 'dump must include last-cycle counts',
      );
    },
  );

  test(
    'progress_logs one-shot: re-queued exactly once, then flagged forever; '
    'the payload always carries event_date (Fix 1)',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      final eventDate = DateTime.utc(2026, 8, 13, 10, 30, 15);
      await db.into(db.progressLogs).insert(
            ProgressLogsCompanion.insert(
              id: const Value(1),
              eventType: 'lesson_completed',
              lessonId: const Value(5),
              teacherId: const Value(1),
              schoolId: const Value(1),
              eventDate: Value(eventDate),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: List.generate(
          2,
          (_) => _page({
            'progress_logs': [
              _progressCatalogRow(
                id: 'plog-other',
                eventDate: '2026-08-01T00:00:00Z',
              ),
            ],
          }),
        ),
        // The one-shot re-queue is rejected permanently -> terminal.
        pushResponses: [_terminalFailure(1)],
        realtimePages: List.generate(
          2,
          (_) => const SyncRealtimePage(events: [], latestEventId: 0),
        ),
      );
      final service = _makeService(db, store, remote);

      await service.onConnectivityRestored(); // cycle 1: re-queue once
      await service.onConnectivityRestored(); // cycle 2: one-shot holds

      final state = await db.syncReconcileStateDao.getFor('progress_logs', 1);
      expect(state, isNotNull);
      expect(state!.attempts, 1,
          reason: 'one-shot: only one re-queue attempt is ever recorded');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty,
          reason: 'no second re-queue after the one-shot');

      // The single pushed INSERT carried event_date (Fix 1 payload).
      expect(remote.pushCalls, hasLength(1));
      final batch = remote.pushCalls.first.single;
      expect(batch.table, 'progress_logs');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload['event_date'], eventDate.toUtc().toIso8601String());
      expect(payload['event_type'], 'lesson_completed');
      expect(payload['lesson_id'], 5);
      expect(payload['teacher_id'], 'teacher-1');
      expect(payload['school_id'], 'school-1');
    },
  );

  test(
    'scheme_of_work with a natural-key match adopts the server id without '
    'queueing an INSERT',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await db.into(db.schemeOfWork).insert(
            SchemeOfWorkCompanion.insert(
              id: const Value(1),
              schoolId: const Value(1),
              teacherId: const Value(1),
              subjectId: const Value(1),
              term: const Value('first'),
              weekNumber: const Value(3),
              topic: const Value('Fractions'),
              objectives: const Value('Understand fractions'),
              status: const Value('draft'),
              classLevel: const Value('JSS 1'),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({
            'scheme_of_work': [_sowCatalogRow(id: 'sow-srv-1')],
          }),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final row = await (db.select(db.schemeOfWork)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      expect(row.serverId, 'sow-srv-1',
          reason: 'SoW must adopt the server id via its natural key');
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );

  test(
    'scheme_of_work missing server-side queues a clean INSERT whose payload '
    'resolves teacher/school/subject server uuids from local int FKs',
    () async {
      await _seedSchool(db);
      await _seedTeacher(db);
      await _seedSubject(db, id: 1, name: 'Mathematics', serverId: 'subject-1');
      await db.into(db.schemeOfWork).insert(
            SchemeOfWorkCompanion.insert(
              id: const Value(1),
              schoolId: const Value(1),
              teacherId: const Value(1),
              subjectId: const Value(1),
              term: const Value('first'),
              weekNumber: const Value(3),
              topic: const Value('Fractions'),
              objectives: const Value('Understand fractions'),
              status: const Value('draft'),
              classLevel: const Value('JSS 1'),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          _page({
            'scheme_of_work': [
              _sowCatalogRow(id: 'sow-other', weekNumber: 4),
            ],
          }),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1));
      expect(pending.single.queueTable, 'scheme_of_work');
      expect(pending.single.operation, 'INSERT');
      final payload =
          jsonDecode(pending.single.payload) as Map<String, dynamic>;
      expect(payload['teacher_server_id'], 'teacher-1');
      expect(payload['school_server_id'], 'school-1');
      expect(payload['subject_id'], 'subject-1');
      expect(payload['term'], 'first');
      expect(payload['week_number'], 3);
      expect(payload['topic'], 'Fractions');
      expect(payload['objectives'], 'Understand fractions');
      expect(payload['status'], 'draft');
      expect(payload['class_level'], 'JSS 1');
      expect(
        (await db.syncReconcileStateDao.getFor('scheme_of_work', 1))?.attempts,
        1,
      );
    },
  );

  test(
    'subjects use strict school scoping: a null-schoolId subject is not '
    'reconciled while an in-scope missing subject is healed (Fix 4)',
    () async {
      await _seedSubject(db, id: 1, name: 'Igbo', schoolId: 'school-1');
      await _seedSubject(db, id: 2, name: 'Yoruba', schoolId: null);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            subjectCatalog: [
              {
                'id': 'srv-math',
                'subject_name': 'Mathematics',
                'school_id': 'school-1',
                'is_active': true,
                'deleted_at': null,
              },
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );
      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1),
          reason: 'only the school-scoped missing subject is repaired');
      expect(pending.single.recordLocalId, 1);

      final yoruba = await (db.select(db.subjects)
            ..where((t) => t.id.equals(2)))
          .getSingle();
      expect(yoruba.serverId, isNull,
          reason: 'null-schoolId subject must not be treated as this school');
    },
  );
}
