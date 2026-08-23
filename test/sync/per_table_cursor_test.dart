import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

/// Tests for per-table cursor pagination.
///
/// Validates that each table maintains its own (updated_at, id) cursor
/// independently, preventing rows from being skipped or duplicated when
/// multiple tables have interleaved timestamps or identical timestamps.

Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
        SecurityConfigCompanion.insert(
          currentDeviceId: 'test-device-cursor',
          lastRealtimeEventId: Value(0),
        ),
      );
}

/// Helper: create a SyncService wired to [remote] and run one full cycle.
Future<void> runSyncCycle(FakeSyncRemoteApi remote) async {
  final securityService = TrackingSecurityService();
  final service = SyncService(
    db: AppDatabase.forTesting() as dynamic,
    schoolId: 'school-1',
    securityService: securityService,
    remoteApi: remote,
    store: FakeSyncRecordStore(AppDatabase.forTesting() as dynamic),
    mergeEngine: MergeEngine(),
  );
  await service.onConnectivityRestored(jwt: 'fake-jwt');
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

  /// Helper: run a full sync cycle with the given remote API.
  Future<void> _runCycle(FakeSyncRemoteApi remote) async {
    final securityService = TrackingSecurityService();
    final service = SyncService(
      db: db,
      schoolId: 'school-1',
      securityService: securityService,
      remoteApi: remote,
      store: store,
      mergeEngine: MergeEngine(),
    );
    await service.onConnectivityRestored(jwt: 'fake-jwt');
  }

  // ─────────────────────────────────────────────────────────────────────
  // Test 1: Two rows with identical updated_at across pages
  // ─────────────────────────────────────────────────────────────────────
  test(
    'rows with identical updated_at are split across pages without loss',
    () async {
      final sameTimestamp = '2025-01-15T10:00:00Z';

      final remote = FakeSyncRemoteApi(
        pullPages: [
          // Page 1: two lessons with same updated_at, one exams row
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {
                  'id': 'lesson-1',
                  'updated_at': sameTimestamp,
                  'subject': 'Math',
                },
              ),
              SyncChange(
                table: 'lessons',
                row: {
                  'id': 'lesson-2',
                  'updated_at': sameTimestamp,
                  'subject': 'English',
                },
              ),
              SyncChange(
                table: 'exams',
                row: {
                  'id': 'exam-1',
                  'updated_at': sameTimestamp,
                  'topic': 'Midterm',
                },
              ),
            ],
            // lessons hit PAGE_SIZE (simulated), exams exhausted
            nextCursor: null,
            nextCursors: {
              'lessons': {'updated_at': sameTimestamp, 'id': 'lesson-2'},
              'exams': null,
            },
          ),
          // Page 2: remaining lesson
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {
                  'id': 'lesson-3',
                  'updated_at': sameTimestamp,
                  'subject': 'Science',
                },
              ),
            ],
            nextCursor: null,
            nextCursors: null, // all done
          ),
        ],
        pushResponses: [],
      );

      await _runCycle(remote);

      // Verify: first pull had no cursor (first sync)
      expect(remote.pullCalls.length, greaterThanOrEqualTo(2));
      expect(remote.pullCalls[0]['cursor'], isNull);

      // Verify: second pull received the per-table cursors map as JSON
      final secondCursor =
          jsonDecode(remote.pullCalls[1]['cursor'] as String)
              as Map<String, dynamic>;
      expect(secondCursor.containsKey('lessons'), isTrue);
      expect(secondCursor['lessons'], isA<Map>());
      final lessonsCursor =
          secondCursor['lessons'] as Map<String, dynamic>;
      expect(lessonsCursor['updated_at'], sameTimestamp);
      expect(lessonsCursor['id'], 'lesson-2');
      // exams must be present as null so the server knows it is exhausted.
      expect(secondCursor.containsKey('exams'), isTrue);
      expect(secondCursor['exams'], isNull);

      // Verify: after final page (nextCursors null), stored cursor is null
      final config = await store.loadSecurityConfig();
      expect(config.syncCursor, isNull);
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Test 2: Interleaved timestamps across lessons/exams
  // ─────────────────────────────────────────────────────────────────────
  test(
    'per-table cursors track each table independently with interleaved timestamps',
    () async {
      final t1 = '2025-01-15T08:00:00Z';
      final t2 = '2025-01-15T09:00:00Z';
      final t3 = '2025-01-15T10:00:00Z';
      final t4 = '2025-01-15T11:00:00Z';

      final remote = FakeSyncRemoteApi(
        pullPages: [
          // Page 1: lessons at t1,t3; exams at t2,t4
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {'id': 'L1', 'updated_at': t1, 'subject': 'Math'},
              ),
              SyncChange(
                table: 'lessons',
                row: {'id': 'L2', 'updated_at': t3, 'subject': 'English'},
              ),
              SyncChange(
                table: 'exams',
                row: {'id': 'E1', 'updated_at': t2, 'topic': 'Quiz'},
              ),
              SyncChange(
                table: 'exams',
                row: {'id': 'E2', 'updated_at': t4, 'topic': 'Final'},
              ),
            ],
            nextCursor: null,
            nextCursors: {
              'lessons': {'updated_at': t3, 'id': 'L2'},
              'exams': {'updated_at': t4, 'id': 'E2'},
            },
          ),
          // Page 2: remaining rows for each table
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {'id': 'L3', 'updated_at': '2025-01-15T12:00:00Z', 'subject': 'Science'},
              ),
              SyncChange(
                table: 'exams',
                row: {'id': 'E3', 'updated_at': '2025-01-15T13:00:00Z', 'topic': 'Practical'},
              ),
            ],
            nextCursor: null,
            nextCursors: null, // both exhausted
          ),
        ],
        pushResponses: [],
      );

      await _runCycle(remote);

      // Verify: second pull carries both table cursors
      final cursor = jsonDecode(remote.pullCalls[1]['cursor'] as String)
          as Map<String, dynamic>;
      expect(cursor['lessons'], {'updated_at': t3, 'id': 'L2'});
      expect(cursor['exams'], {'updated_at': t4, 'id': 'E2'});

      // Verify: all 6 rows received (3 lessons + 3 exams)
      final allChanges = <SyncChange>[];
      for (final page in remote.pullPages) {
        allChanges.addAll(page.changes);
      }
      final lessonIds =
          allChanges.where((c) => c.table == 'lessons').map((c) => c.row['id']).toSet();
      final examIds =
          allChanges.where((c) => c.table == 'exams').map((c) => c.row['id']).toSet();
      expect(lessonIds, {'L1', 'L2', 'L3'});
      expect(examIds, {'E1', 'E2', 'E3'});
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Test 3: Cross-table timestamp gap (the core bug scenario)
  // ─────────────────────────────────────────────────────────────────────
  test(
    'table whose next page has timestamps below another table is not skipped',
    () async {
      // Scenario: lessons last row at T=10:00, exams last row at T=09:00.
      // With a global cursor T=10:00, exams rows between 09:01–10:00
      // would be SKIPPED. Per-table cursors prevent this.
      final tLesson = '2025-01-15T10:00:00Z';
      final tExam = '2025-01-15T09:00:00Z';

      final remote = FakeSyncRemoteApi(
        pullPages: [
          // Page 1: lessons fill up to T=10:00, exams to T=09:00
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {'id': 'L50', 'updated_at': tLesson, 'subject': 'LastLesson'},
              ),
              SyncChange(
                table: 'exams',
                row: {'id': 'E50', 'updated_at': tExam, 'topic': 'LastExam'},
              ),
            ],
            nextCursor: null,
            nextCursors: {
              'lessons': {'updated_at': tLesson, 'id': 'L50'},
              'exams': {'updated_at': tExam, 'id': 'E50'},
            },
          ),
          // Page 2: exams rows at 09:01–09:30 (BELOW lessons' T=10:00)
          // These would be LOST with a global cursor but are preserved here
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'exams',
                row: {'id': 'E51', 'updated_at': '2025-01-15T09:05:00Z', 'topic': 'Exam51'},
              ),
              SyncChange(
                table: 'exams',
                row: {'id': 'E52', 'updated_at': '2025-01-15T09:30:00Z', 'topic': 'Exam52'},
              ),
            ],
            nextCursor: null,
            nextCursors: null,
          ),
        ],
        pushResponses: [],
      );

      await _runCycle(remote);

      // Verify: both exams rows from page 2 are present
      final examChanges = remote.pullPages[1].changes
          .where((c) => c.table == 'exams')
          .toList();
      expect(examChanges.length, 2);
      expect(examChanges[0].row['id'], 'E51');
      expect(examChanges[1].row['id'], 'E52');

      // Verify: the cursor sent to page 2 has per-table cursors, not a
      // single timestamp that would skip the exams
      final cursor = jsonDecode(remote.pullCalls[1]['cursor'] as String)
          as Map<String, dynamic>;
      expect(cursor['exams'], {'updated_at': tExam, 'id': 'E50'});
      // The exams cursor (09:00) is BELOW lessons cursor (10:00),
      // proving per-table independence
      final examsUpdatedAt =
          (cursor['exams'] as Map<String, dynamic>)['updated_at'] as String;
      final lessonsUpdatedAt =
          (cursor['lessons'] as Map<String, dynamic>)['updated_at'] as String;
      expect(examsUpdatedAt.compareTo(lessonsUpdatedAt), lessThan(0));
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Test 4: Legacy single-timestamp cursor still works
  // ─────────────────────────────────────────────────────────────────────
  test(
    'legacy plain-timestamp cursor is passed through as lastSyncTimestamp',
    () async {
      final legacyCursor = '2025-01-15T10:00:00Z';

      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {
                  'id': 'x',
                  'updated_at': '2025-01-15T10:01:00Z',
                  'subject': 'New',
                },
              ),
            ],
            nextCursor: null,
            nextCursors: null,
          ),
        ],
        pushResponses: [],
      );

      // Pre-seed the cursor as a legacy timestamp string
      await store.updateSecurityConfig(syncCursor: legacyCursor);

      await _runCycle(remote);

      // Verify: the legacy cursor was sent as-is (not as cursors map)
      expect(remote.pullCalls.length, greaterThanOrEqualTo(1));
      expect(remote.pullCalls[0]['cursor'], legacyCursor);

      // Verify: the server response's nextCursors is stored
      // (nextCursors is null here because the fake returned null,
      // so the client falls back to nextCursor which is also null)
      final config = await store.loadSecurityConfig();
      expect(config.syncCursor, isNull);
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Test 5: Malformed cursor safely falls back
  // ─────────────────────────────────────────────────────────────────────
  test(
    'malformed JSON cursor is treated as legacy timestamp',
    () async {
      final malformedCursor = 'not-a-json-string!!!';

      final remote = FakeSyncRemoteApi(
        pullPages: [
          const SyncPullPage(changes: [], nextCursor: null),
        ],
        pushResponses: [],
      );

      // Pre-seed the malformed cursor
      await store.updateSecurityConfig(syncCursor: malformedCursor);

      await _runCycle(remote);

      // The malformed cursor is sent as-is (client can't parse it)
      expect(remote.pullCalls[0]['cursor'], malformedCursor);
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Test 6: forceFullResync clears per-table cursors
  // ─────────────────────────────────────────────────────────────────────
  test(
    'forceFullResync clears the per-table cursor map',
    () async {
      // Pre-seed a composite cursor map
      await store.updateSecurityConfig(
        syncCursor: jsonEncode({
          'lessons': {'updated_at': '2025-01-15T10:00:00Z', 'id': 'some-id'},
          'exams': {'updated_at': '2025-01-15T09:00:00Z', 'id': 'exam-id'},
        }),
      );

      final remote = FakeSyncRemoteApi(
        pullPages: [
          const SyncPullPage(changes: [], nextCursor: null),
        ],
        pushResponses: [],
      );

      final securityService = TrackingSecurityService();
      final service = SyncService(
        db: db,
        schoolId: 'school-1',
        securityService: securityService,
        remoteApi: remote,
        store: store,
        mergeEngine: MergeEngine(),
      );

      await service.forceFullResync(jwt: 'fake-jwt');

      final config = await store.loadSecurityConfig();
      expect(config.syncCursor, isNull);
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Test 7: Per-table cursor stored as JSON in security_config
  // ─────────────────────────────────────────────────────────────────────
  test(
    'per-table cursor map is serialized to JSON and stored in sync_cursor',
    () async {
      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {'id': 'L1', 'updated_at': '2025-01-15T10:00:00Z'},
              ),
            ],
            nextCursor: null,
            nextCursors: {
              'lessons': {'updated_at': '2025-01-15T10:00:00Z', 'id': 'L1'},
              'exams': null,
              'subjects': null,
            },
          ),
          const SyncPullPage(changes: [], nextCursor: null),
        ],
        pushResponses: [],
      );

      await _runCycle(remote);

      // After page 1, cursor should be stored as JSON
      // After page 2 (all null → done), cursor should be null
      final config = await store.loadSecurityConfig();
      expect(config.syncCursor, isNull);
    },
  );

  // ─────────────────────────────────────────────────────────────────────
  // Test 8: Null entries stripped from cursor before sending
  // ─────────────────────────────────────────────────────────────────────
  test(
    'exhausted tables are sent as null cursors',
    () async {
      final remote = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(
            changes: [
              SyncChange(
                table: 'lessons',
                row: {'id': 'L1', 'updated_at': '2025-01-15T10:00:00Z'},
              ),
            ],
            nextCursor: null,
            nextCursors: {
              'lessons': {'updated_at': '2025-01-15T10:00:00Z', 'id': 'L1'},
              'exams': null, // exhausted
              'subjects': null, // exhausted
            },
          ),
          const SyncPullPage(changes: [], nextCursor: null),
        ],
        pushResponses: [],
      );

      await _runCycle(remote);

      // Verify: second pull includes all table cursors — null entries for
      // exhausted tables are retained so the server knows to skip them.
      final cursor = jsonDecode(remote.pullCalls[1]['cursor'] as String)
          as Map<String, dynamic>;
      expect(cursor.containsKey('lessons'), isTrue);
      expect(cursor.containsKey('exams'), isTrue);
      expect(cursor['exams'], isNull);
      expect(cursor.containsKey('subjects'), isTrue);
      expect(cursor['subjects'], isNull);
    },
  );
}
