// test/sync/sow_new_subject_sync_test.dart
//
// Regression tests for the new-subject Bulk Generate sync-push path.
//
// When a teacher bulk-generates a Scheme-of-Work for a brand-new subject
// (e.g. "French") that has never been synced, the client queues:
//   1. a `subjects` INSERT          (created by _resolveOrInsertSubjectId)
//   2. a `scheme_of_work` INSERT    (created by _insertWeekRow, carrying a
//                                   `subject_name` field so sync-push can
//                                   resolve the subject even though it has no
//                                   server UUID yet)
//   3. `lessons` INSERTs
//   4. `exams` INSERTs
//
// This test verifies:
//   - the scheme_of_work entry is queued WITH a `subject_name` field,
//   - the topological sort (`_tablePriority`) places the `subjects` entry
//     BEFORE the `scheme_of_work` entry so the server can create the subject
//     first,
//   - pushing the subject first resolves the reference (the batch order and
//     payload are inspected directly).
//
// No live server is used — the remote API is FakeSyncRemoteApi and the local
// DB is AppDatabase.forTesting().
import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:classai/core/utils/payload_compressor.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

Future<void> _seedConfig(AppDatabase db) async {
  // Direct insert to bypass updateConfig() which auto-creates sync queue entries
  await db.into(db.securityConfig).insert(
    SecurityConfigCompanion.insert(
      currentDeviceId: 'test-device-sow',
      lastRealtimeEventId: Value(0),
    ),
  );
}

/// Seeds a minimal school + teacher with NO subject rows (fresh install).
Future<int> _seedSchoolAndTeacher(AppDatabase db) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000A01'),
          schoolName: 'New Subject School',
          shortCode: 'NS101',
          subscriptionTier: const Value('free'),
        ),
      );

  await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000A02'),
          email: 'teacher@newsubject.local',
          teacherName: 'Test Teacher',
          role: Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000A01'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );

  return schoolId;
}

SyncService _buildService(
  AppDatabase db,
  FakeSyncRemoteApi remote,
  FakeSyncRecordStore store,
) {
  return SyncService(
    db: db,
    schoolId: 'school-new-subject',
    securityService: TrackingSecurityService(),
    remoteApi: remote,
    store: store,
    mergeEngine: MergeEngine(),
    isForeground: false,
    sessionKeyValid: true,
    biometricAvailable: false,
  );
}

Map<String, dynamic> _decodePayload(String payload) {
  final decoded = jsonDecode(payload);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return decoded.cast<String, dynamic>();
  throw FormatException('Sync payload is not a JSON object');
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

  test('bulk generate for a brand-new subject queues a subject INSERT and a '
      'scheme_of_work INSERT with subject_name', () async {
    final schoolId = await _seedSchoolAndTeacher(db);

    // Fresh install: no subject rows exist yet.
    final existingSubjects = await db.subjectsDao.getAll();
    expect(existingSubjects, isEmpty,
        reason: 'test must start from a DB with no subject');

    final teacherId = (await db.teachersDao.getAll()).first.localId;

    await SchemeOfWorkService(db).saveScheme(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'French',
      classLevel: 'JSS 1',
      term: 'First',
      weeks: [
        {'week': 1, 'topic': 'Introduction', 'objectives': 'Greetings'},
      ],
    );

    // Queue now holds subjects + scheme_of_work + lessons + exams INSERTs.
    final pending = await store.loadPendingQueue();
    final tables = pending.map((e) => e.queueTable).toSet();
    expect(tables, contains('subjects'));
    expect(tables, contains('scheme_of_work'));
    expect(tables, contains('lessons'));
    expect(tables, contains('exams'));

    // The scheme_of_work INSERT must carry a subject_name field so sync-push
    // can resolve the subject even though subject_id is not a valid UUID yet.
    final sowEntry = pending.firstWhere(
      (e) => e.queueTable == 'scheme_of_work' && e.operation == 'INSERT',
    );
    final sowPayload = _decodePayload(sowEntry.payload);
    expect(sowPayload['subject_name'], 'French',
        reason: 'scheme_of_work INSERT must include subject_name for the '
            'new-subject sync-push fix');
    expect(sowPayload['subject_id'], isNull,
        reason: 'a brand-new subject has no server UUID yet');
  });

  test('topological sort places the subjects INSERT before scheme_of_work '
      'INSERT', () async {
    final schoolId = await _seedSchoolAndTeacher(db);
    final teacherId = (await db.teachersDao.getAll()).first.localId;

    await SchemeOfWorkService(db).saveScheme(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'French',
      classLevel: 'JSS 1',
      term: 'First',
      weeks: [
        {'week': 1, 'topic': 'Introduction', 'objectives': 'Greetings'},
      ],
    );

    final remote = FakeSyncRemoteApi();
    await _buildService(db, remote, store).onConnectivityRestored();

    expect(remote.pushCalls, isNotEmpty,
        reason: 'push must have been attempted for the queued entries');

    // The first push call carries the full sorted batch. Verify that the
    // subjects INSERT precedes every scheme_of_work INSERT.
    final firstPush = remote.pushCalls.first;
    final subjectIdx = firstPush.indexWhere(
        (b) => b.table == 'subjects' && b.operation == 'INSERT');
    final sowIdx = firstPush.indexWhere(
        (b) => b.table == 'scheme_of_work' && b.operation == 'INSERT');

    expect(subjectIdx, isNot(-1), reason: 'subjects INSERT was queued');
    expect(sowIdx, isNot(-1), reason: 'scheme_of_work INSERT was queued');
    expect(subjectIdx < sowIdx, isTrue,
        reason: '_tablePriority must push subjects (2) before '
            'scheme_of_work (6) so the server creates the subject first');

    // The scheme_of_work INSERT that reaches the server still carries
    // subject_name (decompressed from the short-key payload).
    final sowBatch = firstPush[sowIdx];
    final decompressed = PayloadCompressor.decompress(sowBatch.record);
    expect(decompressed['subject_name'], 'French');
  });

  test('pushing the subject INSERT first lets the server resolve the '
      'scheme_of_work subject by name', () async {
    final schoolId = await _seedSchoolAndTeacher(db);
    final teacherId = (await db.teachersDao.getAll()).first.localId;

    await SchemeOfWorkService(db).saveScheme(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'French',
      classLevel: 'JSS 1',
      term: 'First',
      weeks: [
        {'week': 1, 'topic': 'Introduction', 'objectives': 'Greetings'},
      ],
    );

    final remote = FakeSyncRemoteApi();
    await _buildService(db, remote, store).onConnectivityRestored();

    final firstPush = remote.pushCalls.first;

    // Simulate the resolution: the subjects INSERT (which is pushed first)
    // carries the subject name, and the scheme_of_work INSERT carries the
    // matching subject_name. The server-side resolver (resolveForeignKeys)
    // matches scheme_of_work.subject_name -> subjects.name when subject_id is
    // not a valid UUID.
    final subjectBatch = firstPush.firstWhere(
        (b) => b.table == 'subjects' && b.operation == 'INSERT');
    final subjectPayload = PayloadCompressor.decompress(subjectBatch.record);
    expect(subjectPayload['name'], 'French');

    final sowBatch = firstPush.firstWhere(
        (b) => b.table == 'scheme_of_work' && b.operation == 'INSERT');
    final sowPayload = PayloadCompressor.decompress(sowBatch.record);

    // The subject name in both payloads matches — the resolver can link them.
    expect(sowPayload['subject_name'], subjectPayload['name'],
        reason: 'scheme_of_work.subject_name must match subjects.name so the '
            'server-side resolver can link the new scheme to the new subject');
  });
}
