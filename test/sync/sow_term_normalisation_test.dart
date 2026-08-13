// test/sync/sow_term_normalisation_test.dart
//
// Regression tests for the stuck scheme_of_work sync.
//
// Root cause: the server table `scheme_of_work` has a CHECK constraint
// (`scheme_of_work_term_check`) that only accepts the lowercase values
// 'first' / 'second' / 'third'. The client queued title-case terms
// ('First', 'Second', 'Third'), so every scheme_of_work INSERT/UPDATE was
// rejected with "violates check constraint" and retried forever.
//
// The fix has two halves:
//   1. Every scheme_of_work payload builder normalises the term through
//      `normalizeSowTermForServer` before queuing, and
//   2. `SyncService._pushChanges` self-heals entries already sitting in the
//      queue with title-case terms: it normalises the payload AND persists
//      the corrected payload back to the queue (`updateEntryPayload`), so
//      the already-pending entries succeed on the next sync.
//
// No live server is used — the remote API is FakeSyncRemoteApi and the local
// DB is AppDatabase.forTesting().
import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:classai/core/utils/payload_compressor.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

Future<void> _seedConfig(AppDatabase db) async {
  // Direct insert to bypass updateConfig() which auto-creates sync queue entries
  await db.into(db.securityConfig).insert(
    SecurityConfigCompanion.insert(
      currentDeviceId: 'test-device-sow-term',
      lastRealtimeEventId: Value(0),
    ),
  );
}

/// Seeds a minimal school + teacher + subject + one scheme_of_work row (with
/// the given [term], NO server id — a fresh row awaiting its first sync) and
/// returns the scheme row's local id. [n] varies the server UUIDs so multiple
/// calls can coexist in one test.
Future<int> _seedSchemeRow(
  AppDatabase db, {
  required String term,
  int n = 1,
}) async {
  final schoolServerId = '00000000-0000-0000-0000-00000000010$n';
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: Value(schoolServerId),
          schoolName: 'Test School $n',
          shortCode: 'TS10$n',
          subscriptionTier: const Value('free'),
        ),
      );

  final teacherId = await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: Value('00000000-0000-0000-0000-00000000020$n'),
          email: 'teacher$n@testschool.local',
          teacherName: 'Test Teacher $n',
          role: Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: Value(schoolServerId),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );

  final subjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-00000000030$n',
    name: 'Mathematics $n',
    schoolId: schoolServerId,
    sortOrder: 1,
  );

  return db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          schoolId: Value(schoolId),
          teacherId: Value(teacherId),
          subjectId: Value(subjectId),
          term: Value(term),
          weekNumber: const Value(1),
          topic: const Value('Algebraic Expressions'),
          objectives: const Value('Understand variables'),
          status: const Value('draft'),
          classLevel: const Value('JSS 1'),
        ),
      );
}

/// Queues a scheme_of_work INSERT sync entry whose payload carries the raw
/// (possibly title-case) [term]. Server ids must match [_seedSchemeRow] for
/// the same [n].
Future<void> _queueSowInsert(
  AppDatabase db, {
  required int recordLocalId,
  required String term,
  int n = 1,
}) {
  return db.syncQueueDao.insertEntry(
    queueTable: 'scheme_of_work',
    recordLocalId: recordLocalId,
    operation: 'INSERT',
    payload: {
      'teacher_server_id': '00000000-0000-0000-0000-00000000020$n',
      'school_server_id': '00000000-0000-0000-0000-00000000010$n',
      'subject_id': '00000000-0000-0000-0000-00000000030$n',
      'term': term,
      'week_number': 1,
      'topic': 'Algebraic Expressions',
      'objectives': 'Understand variables',
      'status': 'draft',
      'class_level': 'JSS 1',
    },
  );
}

SyncService _buildService(
  AppDatabase db,
  FakeSyncRemoteApi remote,
  FakeSyncRecordStore store,
) {
  return SyncService(
    db: db,
    schoolId: 'school-sow-term',
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

  group('normalizeSowTermForServer helper', () {
    test('maps title-case and ordinal aliases to the lowercase server value',
        () {
      expect(normalizeSowTermForServer('First'), 'first');
      expect(normalizeSowTermForServer('1st'), 'first');
      expect(normalizeSowTermForServer('1st Term'), 'first');
      expect(normalizeSowTermForServer('  First  '), 'first');
      expect(normalizeSowTermForServer('Second'), 'second');
      expect(normalizeSowTermForServer('2nd'), 'second');
      expect(normalizeSowTermForServer('2nd term'), 'second');
      expect(normalizeSowTermForServer('Third'), 'third');
      expect(normalizeSowTermForServer('3rd'), 'third');
      expect(normalizeSowTermForServer('3rd Term'), 'third');
    });

    test('lowercases unknown terms without changing their value', () {
      expect(normalizeSowTermForServer('first'), 'first');
      expect(normalizeSowTermForServer('second'), 'second');
      expect(normalizeSowTermForServer('third'), 'third');
      expect(normalizeSowTermForServer('Holiday'), 'holiday');
      expect(normalizeSowTermForServer(''), '');
    });
  });

  group('scheme_of_work term normalisation at the source', () {
    test('outgoing scheme_of_work INSERT payload sends a lowercase term',
        () async {
      final schemeId = await _seedSchemeRow(db, term: 'First');
      await _queueSowInsert(db, recordLocalId: schemeId, term: 'First');

      final remote = FakeSyncRemoteApi();
      await _buildService(db, remote, store).onConnectivityRestored();

      expect(remote.pushCalls, isNotEmpty,
          reason: 'push must have been attempted for the queued entry');
      final batch = remote.pushCalls.first
          .singleWhere((b) => b.table == 'scheme_of_work');
      expect(batch.operation, 'INSERT');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload['term'], 'first',
          reason: 'the term sent to the server must satisfy '
              'scheme_of_work_term_check');
    });

    test('queued payload is persisted back with the lowercase term', () async {
      final schemeId = await _seedSchemeRow(db, term: 'First');
      await _queueSowInsert(db, recordLocalId: schemeId, term: 'First');

      // Make the push FAIL retryably so the entry stays in the queue and the
      // persisted payload can be inspected afterwards.
      final remote = FakeSyncRemoteApi(
        pushResponses: [
          SyncPushResponse(results: [
            SyncPushResult(
              localId: schemeId,
              status: 'error',
              serverId: null,
              retryable: true,
            ),
          ]),
        ],
      );
      await _buildService(db, remote, store).onConnectivityRestored();

      final rows = await (db.select(db.syncQueue)
            ..where((t) => t.queueTable.equals('scheme_of_work')))
          .get();
      expect(rows, hasLength(1),
          reason: 'the retryable failure must leave the entry pending');
      final payload = _decodePayload(rows.first.payload);
      expect(payload['term'], 'first',
          reason: 'the self-heal must persist the corrected term back to the '
              'queue so the next push succeeds');
    });

    test('Second → second and Third → third in outgoing payloads', () async {
      final idSecond = await _seedSchemeRow(db, term: 'Second', n: 1);
      final idThird = await _seedSchemeRow(db, term: 'Third', n: 2);
      await _queueSowInsert(db, recordLocalId: idSecond, term: 'Second', n: 1);
      await _queueSowInsert(db, recordLocalId: idThird, term: 'Third', n: 2);

      final remote = FakeSyncRemoteApi();
      await _buildService(db, remote, store).onConnectivityRestored();

      final batches = remote.pushCalls.first
          .where((b) => b.table == 'scheme_of_work')
          .toList();
      expect(batches, hasLength(2));
      final terms = batches
          .map((b) => PayloadCompressor.decompress(b.record)['term'] as String)
          .toSet();
      expect(terms, {'second', 'third'});
    });

    test('a lowercase term is not changed', () async {
      final schemeId = await _seedSchemeRow(db, term: 'first');
      await _queueSowInsert(db, recordLocalId: schemeId, term: 'first');

      final remote = FakeSyncRemoteApi();
      await _buildService(db, remote, store).onConnectivityRestored();

      final batch = remote.pushCalls.first
          .singleWhere((b) => b.table == 'scheme_of_work');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload['term'], 'first');

      // Nothing was rewritten: the stored payload still says 'first'.
      final rows = await (db.select(db.syncQueue)
            ..where((t) => t.queueTable.equals('scheme_of_work')))
          .get();
      // The push succeeded, so the entry was removed from the queue.
      expect(rows, isEmpty);
    });
  });
}
