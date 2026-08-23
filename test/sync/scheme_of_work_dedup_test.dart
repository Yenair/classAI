// test/sync/scheme_of_work_dedup_test.dart
//
// Tests for the scheme_of_work duplicate-handling proposal:
//   1. Pull natural-key guard prevents duplicate INSERT
//   2. Pull natural-key guard preserves local non-empty content
//   3. Push-result duplicate cleanup for scheme_of_work
//   4. No data loss: merge keeps newer non-empty fields
//   5. Admin-confirmed merge removes duplicates
//   6. No duplicate INSERT after full pull
//   7. Pull merge duplicates are merged, not deleted

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

// ── Helpers ─────────────────────────────────────────────────────────────

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
  String schoolId = 'school-1',
}) async {
  await db.into(db.subjects).insert(
    SubjectsCompanion.insert(
      id: Value(id),
      name: name,
      serverId: serverId != null ? Value(serverId) : const Value.absent(),
      schoolId: Value(schoolId),
    ),
  );
}

Future<void> _seedScheme(
  AppDatabase db, {
  required int id,
  String? serverId,
  int schoolId = 1,
  int teacherId = 1,
  int subjectId = 1,
  String term = 'first',
  int weekNumber = 1,
  String topic = 'Grammar',
  String objectives = '',
  String status = 'draft',
  String? adminEditedTopic,
  String? adminComment,
  String classLevel = '',
}) async {
  await db.into(db.schemeOfWork).insert(
    SchemeOfWorkCompanion.insert(
      id: Value(id),
      serverId: serverId != null ? Value(serverId) : const Value.absent(),
      schoolId: Value(schoolId),
      teacherId: Value(teacherId),
      subjectId: Value(subjectId),
      term: Value(term),
      weekNumber: Value(weekNumber),
      topic: Value(topic),
      objectives: Value(objectives),
      status: Value(status),
      adminEditedTopic: adminEditedTopic != null
          ? Value(adminEditedTopic)
          : const Value.absent(),
      adminComment:
          adminComment != null ? Value(adminComment) : const Value.absent(),
      classLevel: Value(classLevel),
    ),
  );
}

Future<void> _seedAllFks(AppDatabase db) async {
  await _seedSchool(db);
  await _seedTeacher(db);
  await _seedSubject(db, id: 1, name: 'English Studies', serverId: 'subject-1');
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

// ── Tests ───────────────────────────────────────────────────────────────

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
    'pull natural-key guard prevents duplicate INSERT',
    () async {
      await _seedAllFks(db);
      // Local row with same natural key, no server_id.
      await _seedScheme(db,
          id: 1, serverId: null, topic: 'Old Topic', weekNumber: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'scheme_of_work',
                row: {
                  'server_id': 'sow-new',
                  'school_id': 'school-1',
                  'teacher_id': 'teacher-1',
                  'subject_id': 'subject-1',
                  'term': 'first',
                  'week_number': 1,
                  'topic': 'New Topic',
                  'objectives': '',
                  'status': 'draft',
                  'class_level': '',
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                },
              ),
            ],
            nextCursor: null,
          ),
        ],
        pushResponses: [],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final rows = await db.select(db.schemeOfWork).get();
      expect(rows.length, 1);
      expect(rows.first.serverId, 'sow-new');
      expect(rows.first.topic, 'New Topic');
    },
  );

  test(
    'pull natural-key guard preserves local non-empty content',
    () async {
      await _seedAllFks(db);
      // Local row with admin-edited topic.
      await _seedScheme(db,
          id: 1,
          serverId: null,
          topic: 'Admin Edited',
          adminEditedTopic: 'Admin Topic',
          adminComment: 'keep this',
          weekNumber: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'scheme_of_work',
                row: {
                  'server_id': 'sow-new',
                  'school_id': 'school-1',
                  'teacher_id': 'teacher-1',
                  'subject_id': 'subject-1',
                  'term': 'first',
                  'week_number': 1,
                  'topic': '',
                  'objectives': '',
                  'status': 'draft',
                  'admin_edited_topic': '',
                  'admin_comment': '',
                  'class_level': '',
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                },
              ),
            ],
            nextCursor: null,
          ),
        ],
        pushResponses: [],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final rows = await db.select(db.schemeOfWork).get();
      expect(rows.length, 1);
      expect(rows.first.serverId, 'sow-new');
      // Local content is preserved because remote fields were empty.
      expect(rows.first.topic, 'Admin Edited');
      expect(rows.first.adminEditedTopic, 'Admin Topic');
      expect(rows.first.adminComment, 'keep this');
    },
  );

  test(
    'push-result duplicate cleanup for scheme_of_work',
    () async {
      await _seedAllFks(db);
      // Two rows sharing the same server_id (simulates crash gap).
      await _seedScheme(db,
          id: 1, serverId: 'sow-1', topic: 'old', weekNumber: 1);
      await _seedScheme(db,
          id: 2, serverId: 'sow-1', topic: 'new', weekNumber: 1);

      // Queue INSERT for id=2 (the pushed row).
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: 2,
        operation: 'INSERT',
        payload: {
          'local_id': 2,
          'topic': 'new',
          'server_id': 'sow-1',
        },
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 2,
                status: 'created',
                serverId: 'sow-1',
                retryable: false,
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Only canonical row (id=1) remains.
      final rows = await db.select(db.schemeOfWork).get();
      expect(rows.length, 1);
      expect(rows.first.id, 1);
      expect(rows.first.topic, 'new'); // merged from pushed row
      expect(rows.first.serverId, 'sow-1');

      // Queue entry for id=2 is terminal.
      final queue = await (db.select(db.syncQueue)
            ..where((t) => t.recordLocalId.equals(2)))
          .get();
      if (queue.isNotEmpty) {
        expect(queue.first.isTerminal, true);
      }
    },
  );

  test(
    'no data loss: merge keeps newer non-empty fields',
    () async {
      await _seedAllFks(db);
      // Canonical with preserved content.
      await _seedScheme(db,
          id: 1,
          serverId: 'sow-1',
          topic: 'A',
          objectives: 'obj-A',
          adminComment: 'keep this',
          classLevel: 'JSS1',
          status: 'draft',
          weekNumber: 1);
      // Source with newer content.
      await _seedScheme(db,
          id: 2,
          serverId: 'sow-1',
          topic: '',
          objectives: 'obj-B',
          adminComment: 'new comment',
          classLevel: '',
          status: 'approved',
          weekNumber: 1);

      // Queue INSERT for id=2 (the pushed row).
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: 2,
        operation: 'INSERT',
        payload: {
          'local_id': 2,
          'server_id': 'sow-1',
          'topic': '',
          'objectives': 'obj-B',
          'admin_comment': 'new comment',
          'class_level': '',
          'status': 'approved',
        },
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 2,
                status: 'created',
                serverId: 'sow-1',
                retryable: false,
              ),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final row = await (db.select(db.schemeOfWork)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      // Local non-empty preserved (remote was empty).
      expect(row.topic, 'A');
      expect(row.classLevel, 'JSS1');
      // Pushed local row's non-empty fields win over canonical.
      expect(row.adminComment, 'new comment');
      expect(row.objectives, 'obj-B');
      expect(row.status, 'approved');
    },
  );

  test(
    'admin-confirmed merge removes duplicates',
    () async {
      await _seedAllFks(db);
      await _seedScheme(db,
          id: 1, serverId: 'sow-1', topic: 'A', weekNumber: 1);
      await _seedScheme(db,
          id: 2, serverId: 'sow-1', topic: 'B', weekNumber: 1);
      await _seedScheme(db,
          id: 3, serverId: 'sow-1', topic: 'C', weekNumber: 1);

      // Queue entry for id=2.
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: 2,
        operation: 'INSERT',
        payload: {'local_id': 2, 'topic': 'B'},
      );

      final groups =
          await db.schemeOfWorkDao.findDuplicateServerIdGroups();
      expect(groups.length, 1);
      expect(groups.first.length, 3);

      // Merge: keep id=1, delete ids 2 and 3.
      final deleteIds = groups.first.skip(1).map((r) => r.id).toList();
      await db.schemeOfWorkDao.mergeAndDeleteGroup(deleteIds: deleteIds);

      // Mark orphan queue entries terminal.
      for (final delId in deleteIds) {
        final orphans = await (db.select(db.syncQueue)
              ..where((t) =>
                  t.queueTable.equals('scheme_of_work') &
                  t.recordLocalId.equals(delId)))
            .get();
        for (final q in orphans) {
          await (db.update(db.syncQueue)
                ..where((t) => t.id.equals(q.id)))
              .write(SyncQueueCompanion(
            isTerminal: const Value(true),
            lastError: const Value('Duplicate merged'),
          ));
        }
      }

      final rows = await db.select(db.schemeOfWork).get();
      expect(rows.length, 1);
      expect(rows.first.id, 1);
    },
  );

  test(
    'no duplicate INSERT after full pull with natural-key guard',
    () async {
      await _seedAllFks(db);
      // Local row with natural key, no server_id.
      await _seedScheme(db,
          id: 1, serverId: null, topic: 'Existing', weekNumber: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'scheme_of_work',
                row: {
                  'server_id': 'sow-pulled',
                  'school_id': 'school-1',
                  'teacher_id': 'teacher-1',
                  'subject_id': 'subject-1',
                  'term': 'first',
                  'week_number': 1,
                  'topic': 'Pulled Content',
                  'objectives': '',
                  'status': 'draft',
                  'class_level': '',
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                },
              ),
            ],
            nextCursor: null,
          ),
        ],
        pushResponses: [],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      final rows = await db.select(db.schemeOfWork).get();
      expect(rows.length, 1);
      expect(rows.first.serverId, 'sow-pulled');
    },
  );

  test(
    'pull merge duplicates are merged, not deleted',
    () async {
      await _seedAllFks(db);
      // Two rows with same server_id, different content.
      await _seedScheme(db,
          id: 1,
          serverId: 'sow-1',
          topic: 'A',
          objectives: 'obj-A',
          adminComment: null,
          weekNumber: 1);
      await _seedScheme(db,
          id: 2,
          serverId: 'sow-1',
          topic: '',
          objectives: 'obj-B',
          adminComment: 'comment-B',
          weekNumber: 1);

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'scheme_of_work',
                row: {
                  'server_id': 'sow-1',
                  'school_id': 'school-1',
                  'teacher_id': 'teacher-1',
                  'subject_id': 'subject-1',
                  'term': 'first',
                  'week_number': 1,
                  'topic': 'Merged Topic',
                  'objectives': 'merged obj',
                  'status': 'approved',
                  'class_level': 'JSS2',
                  'created_at': DateTime.now().toIso8601String(),
                  'updated_at': DateTime.now().toIso8601String(),
                },
              ),
            ],
            nextCursor: null,
          ),
        ],
        pushResponses: [],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Both rows still exist (not hard-deleted during pull).
      final rows = await db.select(db.schemeOfWork).get();
      expect(rows.length, 2);

      // Canonical (id=1) has merged content.
      final canonical = rows.firstWhere((r) => r.id == 1);
      expect(canonical.topic, 'A'); // local preserved (remote non-empty but canonical kept)
      expect(canonical.adminComment, 'comment-B'); // merged from source
      expect(canonical.objectives, 'obj-B'); // merged from source
    },
  );
}
