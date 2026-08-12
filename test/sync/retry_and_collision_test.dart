// Tests for the two sync-engine defect fixes:
//   1. Retryable push failures must never become terminal from attempt count
//      alone — they stay pending with a per-entry next_retry_at cooldown.
//   2. Push results must be keyed by table + local_id (not bare local_id) so
//      independent auto-increment ids across subjects/lessons/exams/
//      scheme_of_work can never collide.
// Plus the one-time legacy recovery for rows already dropped by the old
// 5-attempt terminal cap.
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

/// A subject row so _updateLocalServerId() has something to write into.
Future<void> _seedSubject(AppDatabase db, {int id = 1}) async {
  await db.into(db.subjects).insert(
        SubjectsCompanion.insert(
          id: Value(id),
          name: 'English Studies',
          schoolId: const Value('school-1'),
        ),
      );
}

/// A lesson row so _updateLocalServerId() has something to write into.
Future<void> _seedLesson(AppDatabase db, {int id = 1}) async {
  await db.into(db.lessons).insert(
        LessonsCompanion.insert(
          id: Value(id),
          serverId: const Value(null),
          subject: 'English Studies',
          classLevel: 'JSS1',
          week: 1,
          topic: 'Grammar',
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
}

/// A scheme_of_work row so _updateLocalServerId() has something to write into.
Future<void> _seedScheme(AppDatabase db, {int id = 1}) async {
  await db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          id: Value(id),
          subjectId: const Value(1),
          term: const Value('first'),
          weekNumber: const Value(1),
          topic: const Value('Grammar'),
          status: const Value('draft'),
        ),
      );
}

/// Simulates the retry cooldown elapsing so the entry can be pushed again.
Future<void> _clearCooldown(AppDatabase db, int entryId) async {
  await (db.update(db.syncQueue)..where((t) => t.id.equals(entryId))).write(
    const SyncQueueCompanion(nextRetryAt: Value(null)),
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
    'retryable failure never becomes terminal — still pending after 6 attempts '
    'with next_retry_at scheduled',
    () async {
      await db.syncQueueDao.insertEntry(
        queueTable: 'subjects',
        recordLocalId: 1,
        operation: 'INSERT',
        payload: {'local_id': 1, 'data': {'name': 'English Studies'}},
      );
      final entryId = (await db.syncQueueDao.pendingEntries()).first.id;

      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: List.generate(
          6,
          (_) => SyncPushResponse(
            results: [
              SyncPushResult(
                localId: 1,
                status: 'error',
                serverId: null,
                retryable: true,
                errorMessage: 'server rejected the insert',
              ),
            ],
          ),
        ),
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      for (var i = 0; i < 6; i++) {
        await service.onConnectivityRestored();
        if (i < 5) {
          // Simulate the cooldown elapsing between cycles.
          await _clearCooldown(db, entryId);
        }
      }

      final pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(1), reason: 'entry must stay pending');
      final entry = pending.first;
      expect(entry.isTerminal, isFalse,
          reason: 'retryable failure must NEVER be terminal from attempts');
      expect(entry.attempts, 6);
      expect(entry.nextRetryAt, isNotNull,
          reason: 'a retry cooldown must be scheduled');
      expect(entry.nextRetryAt!.isAfter(DateTime.now()), isTrue,
          reason: 'next retry must be in the future');
      expect(
        entry.nextRetryAt!.isAfter(DateTime.now().add(const Duration(minutes: 10))),
        isTrue,
        reason: 'backoff should be exponential (30s * 2^5 = 16 min)',
      );
    },
  );

  test('next_retry_at is respected — cooldown entries are skipped, past/null are pushed',
      () async {
        await db.syncQueueDao.insertEntry(
          queueTable: 'subjects',
          recordLocalId: 1,
          operation: 'INSERT',
          payload: {'local_id': 1, 'data': {'name': 'English Studies'}},
        );
        final entryId = (await db.syncQueueDao.pendingEntries()).first.id;

        // Put the entry into cooldown: next_retry_at one hour in the future.
        await (db.update(db.syncQueue)..where((t) => t.id.equals(entryId)))
            .write(
          SyncQueueCompanion(
            nextRetryAt: Value(DateTime.now().add(const Duration(hours: 1))),
          ),
        );

        final remote = FakeSyncRemoteApi(
          pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = _makeService(db, store, remote);

        // Cycle 1: entry still in cooldown → remote push must be skipped.
        await service.onConnectivityRestored();
        expect(remote.pushCalls, isEmpty,
            reason: 'entry in cooldown must not be pushed');
        expect(await db.syncQueueDao.pendingEntries(), hasLength(1),
            reason: 'entry must remain pending during cooldown');

        // Cooldown elapses: next_retry_at in the past → pushed this cycle.
        await (db.update(db.syncQueue)..where((t) => t.id.equals(entryId)))
            .write(
          SyncQueueCompanion(
            nextRetryAt: Value(DateTime.now().subtract(const Duration(minutes: 1))),
          ),
        );

        await service.onConnectivityRestored();
        expect(remote.pushCalls, hasLength(1),
            reason: 'entry with elapsed cooldown must be pushed');
        expect(remote.pushCalls.first.first.table, 'subjects');
        expect(await db.syncQueueDao.pendingEntries(), isEmpty,
            reason: 'successful push removes the entry');
      },
  );

  test('non-retryable failure becomes terminal immediately and is not retried',
      () async {
        await db.syncQueueDao.insertEntry(
          queueTable: 'subjects',
          recordLocalId: 1,
          operation: 'INSERT',
          payload: {'local_id': 1, 'data': {'name': 'English Studies'}},
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
                  errorMessage: 'Admin access required for this table',
                ),
              ],
            ),
          ],
          realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
        );

        final service = _makeService(db, store, remote);
        await service.onConnectivityRestored();

        final terminal = await db.syncQueueDao.terminalEntries();
        expect(terminal, hasLength(1), reason: 'entry must be marked terminal');
        expect(terminal.first.isTerminal, isTrue);
        expect(terminal.first.lastError, contains('Admin access required'));
        expect(terminal.first.failedAt, isNotNull);

        // A second cycle must not retry a terminal entry.
        await service.onConnectivityRestored();
        expect(remote.pushCalls, hasLength(1),
            reason: 'terminal entry must not be pushed again');
      },
  );

  test(
    'cross-table local_id collision — subject 1, lesson 1, scheme 1 each keep '
    'their own server result',
    () async {
      await _seedSubject(db, id: 1);
      await _seedLesson(db, id: 1);
      await _seedScheme(db, id: 1);

      // All three tables share the same numeric local id.
      await db.syncQueueDao.insertEntry(
        queueTable: 'subjects',
        recordLocalId: 1,
        operation: 'INSERT',
        payload: {'local_id': 1, 'data': {'name': 'English Studies'}},
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: 1,
        operation: 'INSERT',
        payload: {'local_id': 1, 'data': {'topic': 'Grammar'}},
      );
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: 1,
        operation: 'INSERT',
        payload: {'local_id': 1, 'data': {'topic': 'Grammar'}},
      );

      // Server echoes one result per change, in the same order as the batch
      // (subjects → lessons → scheme_of_work), all with local_id 1 but
      // distinct server ids.
      final remote = FakeSyncRemoteApi(
        pullPages: [const SyncPullPage(changes: [], nextCursor: null)],
        pushResponses: [
          SyncPushResponse(
            results: [
              SyncPushResult(
                  localId: 1,
                  status: 'created',
                  serverId: 'srv-subjects-1',
                  retryable: false),
              SyncPushResult(
                  localId: 1,
                  status: 'created',
                  serverId: 'srv-lessons-1',
                  retryable: false),
              SyncPushResult(
                  localId: 1,
                  status: 'created',
                  serverId: 'srv-scheme-1',
                  retryable: false),
            ],
          ),
        ],
        realtimePages: [const SyncRealtimePage(events: [], latestEventId: 0)],
      );

      final service = _makeService(db, store, remote);
      await service.onConnectivityRestored();

      // Push order is topological: subjects → lessons → scheme_of_work.
      expect(
        remote.pushCalls.first.map((b) => b.table).toList(),
        ['subjects', 'lessons', 'scheme_of_work'],
      );

      final subject = await (db.select(db.subjects)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      final lesson = await (db.select(db.lessons)
            ..where((t) => t.id.equals(1)))
          .getSingle();
      final scheme = await (db.select(db.schemeOfWork)
            ..where((t) => t.id.equals(1)))
          .getSingle();

      // Each row must receive ITS OWN server id — never another table's.
      expect(subject.serverId, 'srv-subjects-1');
      expect(lesson.serverId, 'srv-lessons-1');
      expect(scheme.serverId, 'srv-scheme-1');

      // All three queue entries were successful and removed.
      expect(await db.syncQueueDao.pendingEntries(), isEmpty);
    },
  );

  test(
    'one-time recovery resets only terminal rows carrying the exact '
    'not-null-constraint signal, and reports the count',
    () async {
      const notNullError = 'null value in column "curriculum" of relation '
          '"subjects" violates not-null constraint';

      // Two dropped retryable rows (the incident class).
      await db.into(db.syncQueue).insert(
            SyncQueueCompanion.insert(
              queueTable: 'subjects',
              recordLocalId: 1,
              operation: 'INSERT',
              payload: '{"local_id":1}',
              attempts: const Value(5),
              isTerminal: const Value(true),
              lastError: const Value(notNullError),
              failedAt: Value(DateTime.now()),
            ),
          );
      await db.into(db.syncQueue).insert(
            SyncQueueCompanion.insert(
              queueTable: 'scheme_of_work',
              recordLocalId: 1,
              operation: 'INSERT',
              payload: '{"local_id":1}',
              attempts: const Value(5),
              isTerminal: const Value(true),
              lastError: const Value(notNullError),
              failedAt: Value(DateTime.now()),
            ),
          );

      // One terminal row that must NOT be reset (different, non-retryable
      // failure signal).
      await db.into(db.syncQueue).insert(
            SyncQueueCompanion.insert(
              queueTable: 'teachers',
              recordLocalId: 1,
              operation: 'UPDATE',
              payload: '{"local_id":1}',
              attempts: const Value(5),
              isTerminal: const Value(true),
              lastError: const Value('Admin access required for this table'),
              failedAt: Value(DateTime.now()),
            ),
          );

      final recovered = await store.recoverRetryableTerminalRows();
      expect(recovered, 2,
          reason: 'exactly the two not-null-constraint rows must be reset');

      final pending = await db.syncQueueDao.pendingEntries();
      expect(pending, hasLength(2), reason: 'recovered rows must be pending');

      for (final entry in pending) {
        expect(entry.isTerminal, isFalse);
        expect(entry.attempts, 0, reason: 'attempts reset to a clean slate');
        expect(entry.nextRetryAt, isNull, reason: 'no cooldown after recovery');
        expect(entry.failedAt, isNull);
        expect(entry.lastError, isNotNull,
            reason: 'last_error is kept for visibility');
      }

      // The non-retryable row stays terminal.
      final terminal = await db.syncQueueDao.terminalEntries();
      expect(terminal, hasLength(1));
      expect(terminal.first.queueTable, 'teachers');
      expect(terminal.first.lastError, contains('Admin access required'));

      // Idempotent: a second run has nothing left to reset.
      expect(await store.recoverRetryableTerminalRows(), 0);
    },
  );
}
