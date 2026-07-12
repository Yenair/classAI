import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNotNull;
import 'package:classai/core/database/database.dart';
import 'package:classai/core/utils/payload_compressor.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

/// Seed the security config directly (avoids updateConfig which creates
/// sync queue entries for security_config).
Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
    SecurityConfigCompanion.insert(
      currentDeviceId: 'test-device-001',
    ),
  );
}

/// Seed a school record in the Drift schools table.
Future<void> _seedSchool(AppDatabase db,
    {int localId = 1,
    String serverId = 'srv-school-1',
    String shortCode = 'SCH001'}) async {
  await db.into(db.schools).insert(
    SchoolsCompanion.insert(
      localId: Value(localId),
      serverId: Value(serverId),
      schoolName: 'Test School',
      shortCode: shortCode,
    ),
  );
}

/// Seed a lesson record in the Drift lessons table.
Future<int> _seedLesson(
  AppDatabase db, {
  int id = 1,
  String title = 'Algebra Basics',
  String content =
      '{"body":"Lesson about algebra","objectives":["Understand X"],"materials":[],"presentation":"","assessment":"","homework":""}',
  String subject = 'Mathematics',
  String classLevel = 'SS1',
  String topic = 'Algebra',
  String difficulty = 'medium',
  int updateCounter = 0,
  String? serverId,
}) async {
  await db.into(db.lessons).insert(
    LessonsCompanion.insert(
      id: Value(id),
      serverId: Value(serverId),
      subject: subject,
      classLevel: classLevel,
      week: 1,
      topic: topic,
      difficulty: difficulty,
      bloomsVerbs: '["analyze"]',
      curriculum: 'nerdc',
      content: content,
      updateCounter: Value(updateCounter),
      isDeleted: Value(false),
      status: Value('draft'),
      isUnlocked: Value(true),
    ),
  );
  return id;
}

/// Seed an exam record in the Drift exams table.
Future<int> _seedExam(
  AppDatabase db, {
  int id = 1,
  String title = 'Algebra Exam',
  String content =
      '{"mcqs":[{"question":"What is X?","options":["A","B"],"answer":"A"}],"theoryQuestions":[],"markingScheme":"standard"}',
  String subject = 'Mathematics',
  String classLevel = 'SS1',
  String topic = 'Algebra',
  String difficulty = 'medium',
  int updateCounter = 0,
  String? serverId,
}) async {
  await db.into(db.exams).insert(
    ExamsCompanion.insert(
      id: Value(id),
      serverId: Value(serverId),
      subject: subject,
      classLevel: classLevel,
      topic: topic,
      difficulty: difficulty,
      curriculum: 'nerdc',
      content: content,
      updateCounter: Value(updateCounter),
      isDeleted: Value(false),
      isUnlocked: Value(true),
      term: const Value.absent(),
    ),
  );
  return id;
}

/// Establish a merge base for the merge engine.
/// Seeds BOTH the FakeSyncRecordStore baseRecords map (for loadBaseRecordByHash)
/// AND writes to the DB versionHashes table (for _loadBaseHash in the sync service).
Future<void> _seedBase(
  AppDatabase db,
  FakeSyncRecordStore store, {
  required String table,
  required int localId,
  required Map<String, dynamic> snapshot,
}) async {
  store.seedBaseRecord(
    tableName: table,
    localId: localId,
    record: snapshot,
  );
  final snapshotJson = jsonEncode(snapshot);
  final hash = sha256.convert(utf8.encode(snapshotJson)).toString();
  await (db.delete(db.versionHashes)
        ..where((t) =>
            t.table.equals(table) & t.recordLocalId.equals(localId)))
      .go();
  await db.into(db.versionHashes).insert(
    VersionHashesCompanion.insert(
      table: table,
      recordLocalId: localId,
      hash: hash,
      snapshotJson: Value(snapshotJson),
      setAt: DateTime.now(),
    ),
  );
}


/// Seed three sync queue entries for topological order test.
Future<void> _seedTopologicalQueue(AppDatabase db) async {
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
}

void main() {
  group('Data Integrity Audit', () {
    late AppDatabase db;
    late FakeSyncRecordStore store;
    late TrackingSecurityService security;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.initialize();
      await _seedConfig(db);
      store = FakeSyncRecordStore(db);
      security = TrackingSecurityService();
    });

    tearDown(() async {
      await db.close();
    });

    // ──────────────────────────────────────────────────────────────────────────
    // Scenario A: Row Count Parity Between Drift and Supabase After Clean Sync
    // ──────────────────────────────────────────────────────────────────────────
    test(
      'A: Row counts match between remote and local after clean sync',
      () async {
        await _seedSchool(db);
        await _seedLesson(db, id: 1, title: 'Lesson 1');
        await _seedLesson(db, id: 2, title: 'Lesson 2');
        await _seedLesson(db, id: 3, title: 'Lesson 3');
        await _seedExam(db, id: 1, title: 'Exam 1');
        await _seedExam(db, id: 2, title: 'Exam 2');

        for (var i = 1; i <= 3; i++) {
          await _seedBase(db, store,
              table: 'lessons',
              localId: i,
              snapshot: {
                'localId': i,
                'title': 'Lesson $i',
                'content': '{"body":"lesson $i"}',
                'updateCounter': 0,
              });
          // Seed into the fake's local records so the merge engine finds them.
          store.seedLocalRecord('lessons', i, {
            'localId': i,
            'title': 'Lesson $i',
            'content': '{"body":"lesson $i"}',
            'updateCounter': 0,
          });
        }
        for (var i = 1; i <= 2; i++) {
          await _seedBase(db, store,
              table: 'exams',
              localId: i,
              snapshot: {
                'localId': i,
                'title': 'Exam $i',
                'content': '{"mcqs":[]}',
                'updateCounter': 0,
              });
          store.seedLocalRecord('exams', i, {
            'localId': i,
            'title': 'Exam $i',
            'content': '{"mcqs":[]}',
            'updateCounter': 0,
          });
        }

        final remote = FakeSyncRemoteApi(
          pullPages: [
            SyncPullPage(
              changes: [
                SyncChange(table: 'lessons', row: {
                  'localId': 1, 'title': 'Lesson 1',
                  'content': '{"body":"lesson 1"}', 'updateCounter': 0
                }),
                SyncChange(table: 'lessons', row: {
                  'localId': 2, 'title': 'Lesson 2',
                  'content': '{"body":"lesson 2"}', 'updateCounter': 0
                }),
                SyncChange(table: 'lessons', row: {
                  'localId': 3, 'title': 'Lesson 3',
                  'content': '{"body":"lesson 3"}', 'updateCounter': 0
                }),
                SyncChange(table: 'exams', row: {
                  'localId': 1, 'title': 'Exam 1',
                  'content': '{"mcqs":[]}', 'updateCounter': 0
                }),
                SyncChange(table: 'exams', row: {
                  'localId': 2, 'title': 'Exam 2',
                  'content': '{"mcqs":[]}', 'updateCounter': 0
                }),
              ],
              nextCursor: null,
            ),
          ],
          pushResponses: [],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = SyncService(
          db: db,
          schoolId: 'srv-school-1',
          securityService: security,
          remoteApi: remote,
          store: store,
          mergeEngine: MergeEngine(),
          isForeground: false,
          sessionKeyValid: true,
          biometricAvailable: false,
        );

        await service.onConnectivityRestored();

        final versionRows = await db.select(db.versionHashes).get();
        final lessonRows =
            versionRows.where((r) => r.table == 'lessons').toList();
        final examRows =
            versionRows.where((r) => r.table == 'exams').toList();

        expect(lessonRows.length, 3,
            reason: 'Expected 3 version_hash rows for lessons');
        expect(examRows.length, 2,
            reason: 'Expected 2 version_hash rows for exams');

        for (final row in lessonRows) {
          final snap =
              jsonDecode(row.snapshotJson!) as Map<String, dynamic>;
          expect(snap['title'], 'Lesson ${row.recordLocalId}');
        }

        expect(service.state, SyncState.idle);
      },
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Scenario B: Offline-Created Lesson → Reconnect → Push Payload Complete
    // ──────────────────────────────────────────────────────────────────────────
    test(
      'B: Offline-created lesson push payload contains all critical fields',
      () async {
        await _seedSchool(db, serverId: 'srv-school-1');
        await _seedLesson(
          db, id: 1, serverId: null, title: 'Algebra Basics',
          content:
              '{"body":"Solving linear equations","objectives":["Solve X"],"materials":[],"presentation":"","assessment":"","homework":""}',
          subject: 'Mathematics', classLevel: 'SS1', topic: 'Algebra',
          difficulty: 'medium', updateCounter: 1,
        );

        await db.syncQueueDao.insertEntry(
          queueTable: 'lessons',
          recordLocalId: 1,
          operation: 'INSERT',
          payload: {
            'local_id': 1,
            'data': {
              'subject': 'Mathematics', 'classLevel': 'SS1', 'week': 1,
              'topic': 'Algebra', 'difficulty': 'medium',
              'bloomsVerbs': '["analyze"]', 'curriculum': 'nerdc',
              'content':
                  '{"body":"Solving linear equations","objectives":["Solve X"],"materials":[],"presentation":"","assessment":"","homework":""}',
              'content_hash': 'abc123', 'teacher_server_id': 'srv-teacher-1',
              'school_server_id': 'srv-school-1',
              'schedule_of_work_id': null, 'week_number': 1,
              'term': 'Term 1', 'status': 'draft', 'is_unlocked': true,
            },
          },
        );

        final remote = FakeSyncRemoteApi(
          pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
          pushResponses: [],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = SyncService(
          db: db, schoolId: 'srv-school-1',
          securityService: security, remoteApi: remote, store: store,
          mergeEngine: MergeEngine(),
          isForeground: false, sessionKeyValid: true, biometricAvailable: false,
        );

        await service.onConnectivityRestored();

        expect(remote.pushCalls, isNotEmpty,
            reason: 'Push should have been called');

        final lessonBatches =
            remote.pushCalls.first.where((b) => b.table == 'lessons').toList();
        expect(lessonBatches, hasLength(1));
        final batch = lessonBatches.first;
        expect(batch.operation, 'INSERT');

        final payload = PayloadCompressor.decompress(batch.record);
        expect(payload.containsKey('local_id'), isTrue,
            reason: 'local_id should be in push payload');

        final dataFields = payload['data'] as Map<String, dynamic>?;
        expect(dataFields, isNotNull,
            reason: 'Push payload should have a "data" key');

        final expectedFields = [
          'subject', 'classLevel', 'week', 'topic', 'difficulty',
          'bloomsVerbs', 'curriculum', 'content', 'content_hash',
          'teacher_server_id', 'school_server_id', 'week_number',
          'term', 'status', 'is_unlocked',
        ];
        for (final field in expectedFields) {
          expect(dataFields!.containsKey(field), isTrue,
              reason: 'Push payload missing critical field: "$field"');
        }

        // Lesson entry removed (security_config entries may remain).
        final remaining = await db.syncQueueDao.pendingEntries();
        expect(remaining.where((e) => e.queueTable == 'lessons'), isEmpty,
            reason: 'Lesson sync queue entry should have been removed');

        final versionRow = await (db.select(db.versionHashes)
              ..where((t) =>
                  t.table.equals('lessons') & t.recordLocalId.equals(1)))
            .getSingleOrNull();
        expect(versionRow, isNotNull,
            reason: 'Version hash should exist after push');
      },
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Scenario C: Server-Created Exam → Pull → Locally Visible
    // ──────────────────────────────────────────────────────────────────────────
    test(
      'C: Exam created on server appears in version_hashes after pull',
      () async {
        await _seedSchool(db, serverId: 'srv-school-1');
        await _seedExam(db, id: 100, title: 'Local placeholder', updateCounter: 0);

        // Establish merge base AND seed local record so merge engine finds it.
        await _seedBase(db, store,
            table: 'exams', localId: 100,
            snapshot: {
              'localId': 100, 'title': 'Local placeholder',
              'subject': 'Mathematics', 'classLevel': 'SS1',
              'topic': 'Algebra', 'difficulty': 'medium',
              'curriculum': 'nerdc', 'content': '{"mcqs":[]}',
              'updateCounter': 0,
            });
        store.seedLocalRecord('exams', 100, {
          'localId': 100, 'title': 'Local placeholder',
          'subject': 'Mathematics', 'classLevel': 'SS1',
          'topic': 'Algebra', 'difficulty': 'medium',
          'curriculum': 'nerdc', 'content': '{"mcqs":[]}',
          'updateCounter': 0,
        });

        final remote = FakeSyncRemoteApi(
          pullPages: [
            SyncPullPage(
              changes: [
                SyncChange(table: 'exams', row: {
                  'localId': 100, 'title': 'Remote Algebra Exam',
                  'subject': 'Mathematics', 'classLevel': 'SS1',
                  'topic': 'Algebra', 'difficulty': 'hard',
                  'curriculum': 'nerdc',
                  'content': '{"mcqs":[{"q":"What is 2+2?","options":["3","4","5"],"answer":"4"}],"theoryQuestions":[],"markingScheme":"standard"}',
                  'updateCounter': 1,
                  'teacher_server_id': 'srv-teacher-1',
                  'school_server_id': 'srv-school-1',
                  'is_unlocked': false, 'is_deleted': false,
                }),
              ],
              nextCursor: null,
            ),
          ],
          pushResponses: [],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = SyncService(
          db: db, schoolId: 'srv-school-1',
          securityService: security, remoteApi: remote, store: store,
          mergeEngine: MergeEngine(),
          isForeground: false, sessionKeyValid: true, biometricAvailable: false,
        );

        await service.onConnectivityRestored();

        final versionRow = await (db.select(db.versionHashes)
              ..where((t) =>
                  t.table.equals('exams') & t.recordLocalId.equals(100)))
            .getSingleOrNull();
        expect(versionRow, isNotNull,
            reason: 'Version hash should exist for pulled exam (localId=100)');

        final snapshot =
            jsonDecode(versionRow!.snapshotJson!) as Map<String, dynamic>;
        expect(snapshot['title'], 'Remote Algebra Exam',
            reason: 'Merged snapshot should contain the exam title');
        expect(snapshot['subject'], 'Mathematics');
        expect(snapshot['classLevel'], 'SS1');
        expect(snapshot['content'], contains('"mcqs"'));

        expect(remote.pullCalls, hasLength(1));
      },
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Scenario D: Server-Deleted Lesson → Sync → Local Deletion
    // ──────────────────────────────────────────────────────────────────────────
    test(
      'D: Lesson deleted on server is reflected locally after sync',
      () async {
        await _seedSchool(db, serverId: 'srv-school-1');
        await _seedLesson(db, id: 5, title: 'Lesson to Delete',
            topic: 'Lesson to Delete',
            updateCounter: 2, serverId: 'srv-lesson-5');

        await _seedBase(db, store,
            table: 'lessons', localId: 5,
            snapshot: {
              'localId': 5, 'title': 'Lesson to Delete',
              'content': '{"body":"content"}',
              'is_deleted': false, 'updateCounter': 1,
            });
        store.seedLocalRecord('lessons', 5, {
          'localId': 5, 'title': 'Lesson to Delete',
          'content': '{"body":"content"}',
          'is_deleted': false, 'updateCounter': 2,
        });

        final remote = FakeSyncRemoteApi(
          pullPages: [
            SyncPullPage(
              changes: [
                SyncChange(table: 'lessons', row: {
                  'localId': 5, 'title': 'Lesson to Delete',
                  'content': '{"body":"content"}',
                  'is_deleted': true, 'updateCounter': 3,
                }),
              ],
              nextCursor: null,
            ),
          ],
          pushResponses: [],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = SyncService(
          db: db, schoolId: 'srv-school-1',
          securityService: security, remoteApi: remote, store: store,
          mergeEngine: MergeEngine(),
          isForeground: false, sessionKeyValid: true, biometricAvailable: false,
        );

        await service.onConnectivityRestored();

        final versionRow = await (db.select(db.versionHashes)
              ..where((t) =>
                  t.table.equals('lessons') & t.recordLocalId.equals(5)))
            .getSingleOrNull();
        expect(versionRow, isNotNull,
            reason: 'Version hash should exist for localId=5 after sync');

        final snapshot =
            jsonDecode(versionRow!.snapshotJson!) as Map<String, dynamic>;
        expect(snapshot['is_deleted'], true,
            reason: 'Remote is_deleted=true should win in merge');

        final lesson = await (db.select(db.lessons)
              ..where((t) => t.id.equals(5)))
            .getSingle();
        expect(lesson, isNotNull,
            reason: 'Local Drift lesson row should still exist');
      },
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Scenario E1: Conflict Detection — Same Field Diverges on Both Sides
    // ──────────────────────────────────────────────────────────────────────────
    test(
      'E1: Conflict saved when both sides modify the same lesson field',
      () async {
        await _seedSchool(db, serverId: 'srv-school-1');
        await _seedLesson(db, id: 10, title: 'Base title', updateCounter: 1);

        await _seedBase(db, store,
            table: 'lessons', localId: 10,
            snapshot: {
              'localId': 10, 'title': 'Base title',
              'content': 'Base body', 'updateCounter': 1,
            });

        store.seedLocalRecord('lessons', 10, {
          'localId': 10, 'title': 'Local title',
          'content': 'Base body', 'updateCounter': 2,
        });

        final remote = FakeSyncRemoteApi(
          pullPages: [
            SyncPullPage(
              changes: [
                SyncChange(table: 'lessons', row: {
                  'localId': 10, 'title': 'Remote title',
                  'content': 'Base body', 'updateCounter': 2,
                }),
              ],
              nextCursor: null,
            ),
          ],
          pushResponses: [],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = SyncService(
          db: db, schoolId: 'srv-school-1',
          securityService: security, remoteApi: remote, store: store,
          mergeEngine: MergeEngine(),
          isForeground: false, sessionKeyValid: true, biometricAvailable: false,
        );

        await service.onConnectivityRestored();

        expect(store.savedConflicts, isNotEmpty,
            reason: 'A conflict should have been saved');
        final conflict = store.savedConflicts.first;
        expect(conflict['recordType'], 'lessons');
        expect(conflict['recordLocalId'], 10);
        expect(conflict['conflictingFields'], contains('title'),
            reason: 'title field should be in the conflict list');
        // When lwwByUpdateCounter tie and same field diverges: unresolved
        expect(conflict['resolution'], MergeResolution.unresolved.name,
            reason: 'Resolution should be unresolved for same-field conflict');

        final versionRow = await (db.select(db.versionHashes)
              ..where((t) =>
                  t.table.equals('lessons') & t.recordLocalId.equals(10)))
            .getSingleOrNull();
        expect(versionRow, isNotNull);
        final snapshot =
            jsonDecode(versionRow!.snapshotJson!) as Map<String, dynamic>;
        expect(snapshot['title'], 'Remote title');
      },
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Scenario E2: Auto-Merge — Different Fields Diverge (No Conflict)
    // ──────────────────────────────────────────────────────────────────────────
    test(
      'E2: No conflict when local and remote change different fields',
      () async {
        await _seedSchool(db, serverId: 'srv-school-1');
        await _seedLesson(db, id: 20,
            title: 'Base title', content: 'Base body', updateCounter: 1);

        await _seedBase(db, store,
            table: 'lessons', localId: 20,
            snapshot: {
              'localId': 20, 'title': 'Base title',
              'content': 'Base body', 'updateCounter': 1,
            });

        store.seedLocalRecord('lessons', 20, {
          'localId': 20, 'title': 'Local updated title',
          'content': 'Base body', 'updateCounter': 2,
        });

        final remote = FakeSyncRemoteApi(
          pullPages: [
            SyncPullPage(
              changes: [
                SyncChange(table: 'lessons', row: {
                  'localId': 20, 'title': 'Base title',
                  'content': 'Remote body', 'updateCounter': 2,
                }),
              ],
              nextCursor: null,
            ),
          ],
          pushResponses: [],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = SyncService(
          db: db, schoolId: 'srv-school-1',
          securityService: security, remoteApi: remote, store: store,
          mergeEngine: MergeEngine(),
          isForeground: false, sessionKeyValid: true, biometricAvailable: false,
        );

        await service.onConnectivityRestored();

        expect(store.savedConflicts, isEmpty,
            reason: 'No conflict should be saved when different fields diverge');

        final versionRow = await (db.select(db.versionHashes)
              ..where((t) =>
                  t.table.equals('lessons') & t.recordLocalId.equals(20)))
            .getSingleOrNull();
        expect(versionRow, isNotNull);
        final snapshot =
            jsonDecode(versionRow!.snapshotJson!) as Map<String, dynamic>;
        expect(snapshot['title'], 'Local updated title',
            reason: 'Local title change should be preserved');
        expect(snapshot['content'], 'Remote body',
            reason: 'Remote content change should be preserved');
      },
    );

    // ──────────────────────────────────────────────────────────────────────────
    // Scenario F (bonus): Topological Push Order
    // ──────────────────────────────────────────────────────────────────────────
    test(
      'F: Push batches in topological order (schools → subjects → exams)',
      () async {
        await _seedTopologicalQueue(db);

        final remote = FakeSyncRemoteApi(
          pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
          pushResponses: [],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = SyncService(
          db: db, schoolId: 'srv-school-1',
          securityService: security, remoteApi: remote, store: store,
          mergeEngine: MergeEngine(),
          isForeground: false, sessionKeyValid: true, biometricAvailable: false,
        );

        await service.onConnectivityRestored();

        expect(remote.pushCalls, isNotEmpty);

        final orderedTables = remote.pushCalls.first
            .where((batch) =>
                ['schools', 'subjects', 'exams'].contains(batch.table))
            .map((batch) => batch.table)
            .toList();
        expect(orderedTables[0], 'schools');
        expect(orderedTables[1], 'subjects');
        expect(orderedTables[2], 'exams');
        expect(service.state, SyncState.idle);
      },
    );
  });
}
