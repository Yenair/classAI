import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/sync_service.dart';
import '../sync/sync_fakes.dart';

/// Performance test: simulate syncing 1000 lessons.
///
/// This test measures sync throughput and validates that the lesson data
/// pipeline handles bulk operations without timeout or memory issues.
void main() {
  group('1000 Lesson Sync Performance', () {
    late AppDatabase db;
    late FakeSyncRecordStore store;
    late FakeSyncRemoteApi remoteApi;

    setUp(() async {
      db = AppDatabase.forTesting();
      await db.initialize();
      await _seedConfig(db);
      store = FakeSyncRecordStore(db);
      remoteApi = FakeSyncRemoteApi(
        pullPages: [
          SyncPullPage(changes: [], nextCursor: null),
        ],
        pushResponses: [
          SyncPushResponse(results: []),
        ],
        realtimePages: [
          const SyncRealtimePage(events: [], latestEventId: 0),
        ],
      );
    });

    tearDown(() async {
      await db.close();
    });

    /// Seed 1000 sync queue entries simulating lesson inserts.
    Future<void> _seed1000SyncQueueEntries() async {
      for (int i = 0; i < 1000; i++) {
        await db.syncQueueDao.insertEntry(
          queueTable: 'lessons',
          recordLocalId: i + 1,
          operation: 'INSERT',
          payload: {
            'local_id': i + 1,
            'data': {
              'subject': 'Mathematics',
              'topic': 'Algebra Lesson ${i + 1}',
              'content': '{"body": "Lesson content $i"}',
            },
          },
        );
      }
    }

    test('sync queue handles 1000 entries without memory issues', () async {
      final stopwatch = Stopwatch()..start();

      await _seed1000SyncQueueEntries();

      stopwatch.stop();

      // Verify queue size using pendingCount
      final count = await db.syncQueueDao.pendingCount();
      expect(count, 1000);

      // Bulk insert should be reasonably fast
      expect(stopwatch.elapsedMilliseconds, lessThan(30000),
          reason: 'Queueing 1000 entries took too long: '
              '${stopwatch.elapsedMilliseconds}ms');
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('sync queue pending count matches inserted entries', () async {
      await _seed1000SyncQueueEntries();

      final count = await db.syncQueueDao.pendingCount();
      expect(count, 1000);

      final lessonCount = await db.syncQueueDao.pendingCountForTable('lessons');
      expect(lessonCount, 1000);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('can clear 1000 queue entries', () async {
      await _seed1000SyncQueueEntries();

      // Delete all entries via the DAO
      final entries = await db.syncQueueDao.pendingEntries();
      for (final entry in entries) {
        await db.syncQueueDao.deleteById(entry.id);
      }

      final remaining = await db.syncQueueDao.pendingCount();
      expect(remaining, 0);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('SyncService handles onConnectivityRestored with 1000 queued items',
        () async {
      await _seed1000SyncQueueEntries();

      final security = TrackingSecurityService();
      final service = SyncService(
        db: db,
        schoolId: 'school-1',
        securityService: security,
        remoteApi: remoteApi,
        store: store,
        isForeground: false,
        sessionKeyValid: true,
        biometricAvailable: false,
      );

      // onConnectivityRestored should complete without error
      await expectLater(
        service.onConnectivityRestored(),
        completes,
      );
    }, timeout: const Timeout(Duration(seconds: 60)));
  });
}

/// Seed the security config for testing.
Future<void> _seedConfig(AppDatabase db) async {
  await db.securityConfigDao.updateConfig(
    syncCursor: null,
    lastRealtimeEventId: 0,
    syncCooldownUntil: null,
  );
}
