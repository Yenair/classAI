// Regression tests for the permanent fix that clears the retry cooldown on
// dependent queue entries (scheme_of_work / lessons / exams) immediately
// after their subject dependency is healed or adopted by the subject
// self-heal reconciliation (_reconcileLocalSubjects).
//
//   1. A pending scheme_of_work entry stuck in cooldown (attempts=3,
//      next_retry_at in the future) for a subject that is missing
//      server-side → reconciliation repairs the subject (queues its INSERT)
//      and resets the entry's retry state (next_retry_at = NULL, attempts =
//      0, last_attempt_at = NULL) so it becomes due for push.
//   2. A pending lessons entry stuck in cooldown for a subject that is
//      adopted from the server → cooldown reset, subject id adopted.
import 'dart:convert';

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

Map<String, dynamic> _serverSubject(String id, String name) {
  return {
    'id': id,
    'subject_name': name,
    'school_id': 'school-1',
    'is_active': true,
    'deleted_at': null,
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
    'stuck scheme_of_work entry has its cooldown reset when the missing '
    'subject is healed by reconciliation, then is pushed',
    () async {
      // Local subject missing server-side (no server_id yet).
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(1),
              name: 'English Studies',
              schoolId: const Value('school-1'),
            ),
          );

      // Pending scheme_of_work entry stuck in retry cooldown: attempts=3,
      // next_retry_at one hour in the future, last attempt recorded.
      await db.into(db.syncQueue).insert(
            SyncQueueCompanion.insert(
              queueTable: 'scheme_of_work',
              recordLocalId: 1,
              operation: 'INSERT',
              payload: jsonEncode({
                'teacher_server_id': 'srv-teacher-1',
                'school_server_id': 'school-1',
                'subject_id': null,
                'subject_name': 'English Studies',
                'term': 'first',
                'week_number': 1,
                'topic': 'Grammar',
                'status': 'draft',
              }),
              attempts: const Value(3),
              nextRetryAt:
                  Value(DateTime.now().add(const Duration(hours: 1))),
              lastAttemptAt: Value(DateTime.now()),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          // Cycle 1: the server catalog lacks the subject, so reconciliation
          // repairs it (queues the subjects INSERT).
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            subjectCatalog: [
              _serverSubject('srv-math', 'Mathematics'),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Cycle 1: the entry is in cooldown, so it is NOT pushed; the pull
      // reconciles the missing subject and resets the dependent cooldown.
      expect(remote.pushCalls, isEmpty,
          reason: 'entry in cooldown must not be pushed in cycle 1');

      var pending = await db.syncQueueDao.pendingEntries();
      final sow =
          pending.firstWhere((e) => e.queueTable == 'scheme_of_work');
      expect(sow.isTerminal, isFalse, reason: 'entry must stay pending');
      expect(sow.nextRetryAt, isNull,
          reason: 'cooldown must be cleared after the subject is healed');
      expect(sow.attempts, 0,
          reason: 'attempts must reset to a clean slate');
      expect(sow.lastAttemptAt, isNull,
          reason: 'last attempt timestamp must be cleared');
      expect(
        sow.nextRetryAt == null ||
            !sow.nextRetryAt!.isAfter(DateTime.now()),
        isTrue,
        reason: 'entry must be due for push (out of cooldown)',
      );

      // The subject repair was queued alongside the reset.
      expect(
        pending.where((e) => e.queueTable == 'subjects'),
        hasLength(1),
        reason: 'reconciliation must queue the subjects INSERT',
      );

      // Cycle 2: with the cooldown cleared, the scheme_of_work entry is
      // actually pushed (subjects first, then its dependents).
      await service.onConnectivityRestored();

      final pushedTables = remote.pushCalls
          .expand((call) => call)
          .map((b) => b.table)
          .toList();
      expect(pushedTables, contains('scheme_of_work'),
          reason: 'entry must be pushed once its cooldown is cleared');
      pending = await db.syncQueueDao.pendingEntries();
      expect(
        pending.where((e) => e.queueTable == 'scheme_of_work'),
        isEmpty,
        reason: 'successful push removes the entry',
      );
    },
  );

  test(
    'dependent lessons entry has its cooldown reset when the subject is '
    'adopted from the server during reconciliation (case-insensitive match)',
    () async {
      // Local subject with no server_id that exists on the server — the
      // reconciliation adopts the server id.
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(1),
              name: 'English Studies',
              schoolId: const Value('school-1'),
            ),
          );

      // Pending lessons entry stuck in retry cooldown for the same subject;
      // the payload subject is lowercase to exercise the case-insensitive
      // matching.
      await db.into(db.syncQueue).insert(
            SyncQueueCompanion.insert(
              queueTable: 'lessons',
              recordLocalId: 1,
              operation: 'INSERT',
              payload: jsonEncode({
                'teacher_server_id': 'srv-teacher-1',
                'school_server_id': 'school-1',
                'subject': 'english studies',
                'class_level': 'JSS1',
                'topic': 'Grammar',
              }),
              attempts: const Value(3),
              nextRetryAt:
                  Value(DateTime.now().add(const Duration(hours: 1))),
              lastAttemptAt: Value(DateTime.now()),
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
          reason: 'local subject must adopt the server id');

      final pending = await db.syncQueueDao.pendingEntries();
      final lesson = pending.firstWhere((e) => e.queueTable == 'lessons');
      expect(lesson.isTerminal, isFalse, reason: 'entry must stay pending');
      expect(lesson.nextRetryAt, isNull,
          reason: 'cooldown must be cleared after the subject is adopted');
      expect(lesson.attempts, 0,
          reason: 'attempts must reset to a clean slate');
      expect(lesson.lastAttemptAt, isNull,
          reason: 'last attempt timestamp must be cleared');
      expect(
        lesson.nextRetryAt == null ||
            !lesson.nextRetryAt!.isAfter(DateTime.now()),
        isTrue,
        reason: 'entry must be due for push (out of cooldown)',
      );
    },
  );

  test(
    'stuck scheme_of_work entry has its cooldown reset on every successful '
    'pull even when its subject already has a server_id (steady state)',
    () async {
      // Local subject that ALREADY exists server-side (server_id present and
      // matching the pull catalog) — the per-cycle heal/adopt branch never
      // runs for it, so only the broad reset can clear dependent cooldowns.
      await db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              id: const Value(1),
              name: 'English Studies',
              schoolId: const Value('school-1'),
              serverId: const Value('srv-english'),
            ),
          );

      // Pending scheme_of_work entry stuck in retry cooldown: attempts=3,
      // next_retry_at one hour in the future, last attempt recorded.
      await db.into(db.syncQueue).insert(
            SyncQueueCompanion.insert(
              queueTable: 'scheme_of_work',
              recordLocalId: 1,
              operation: 'INSERT',
              payload: jsonEncode({
                'teacher_server_id': 'srv-teacher-1',
                'school_server_id': 'school-1',
                'subject_id': 'srv-english',
                'subject_name': 'English Studies',
                'term': 'first',
                'week_number': 1,
                'topic': 'Grammar',
                'status': 'draft',
              }),
              attempts: const Value(3),
              nextRetryAt:
                  Value(DateTime.now().add(const Duration(hours: 1))),
              lastAttemptAt: Value(DateTime.now()),
            ),
          );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: const [],
            nextCursor: null,
            // The subject exists in the pull catalog with the same id the
            // local row already holds.
            subjectCatalog: [
              _serverSubject('srv-english', 'English Studies'),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // The entry is in cooldown, so it is NOT pushed this cycle; the pull's
      // broad reset must clear its retry state anyway.
      expect(remote.pushCalls, isEmpty,
          reason: 'entry in cooldown must not be pushed in cycle 1');

      final pending = await db.syncQueueDao.pendingEntries();
      final sow =
          pending.firstWhere((e) => e.queueTable == 'scheme_of_work');
      expect(sow.isTerminal, isFalse, reason: 'entry must stay pending');
      expect(sow.nextRetryAt, isNull,
          reason: 'cooldown must be cleared for an existing server subject');
      expect(sow.attempts, 0,
          reason: 'attempts must reset to a clean slate');
      expect(sow.lastAttemptAt, isNull,
          reason: 'last attempt timestamp must be cleared');
      expect(
        sow.nextRetryAt == null ||
            !sow.nextRetryAt!.isAfter(DateTime.now()),
        isTrue,
        reason: 'entry must be due for push (out of cooldown)',
      );

      // No subjects INSERT should have been queued — the subject was already
      // server-side, so nothing was repaired or adopted.
      expect(
        pending.where((e) => e.queueTable == 'subjects'),
        isEmpty,
        reason: 'an existing server subject must not be re-queued',
      );
    },
  );
}
