import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:classai/core/utils/payload_compressor.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

import 'sync_fakes.dart';

/// Regression tests for the sync-push fix:
///   1. `_pushChanges` injects `server_id` into UPDATE/DELETE queue entries
///      that lack it (resolved from the local record), so server-side status
///      changes (approval, submit) actually propagate. The fix is generic —
///      it heals scheme_of_work, lessons and exams alike.
///   2. Client-crafted UPDATE payloads never include `updated_at`, which is
///      what guarantees the server-side `updated_at` bump (sync-push) fires.
///
/// No live Supabase connection is used — the remote API is a fake
/// (FakeSyncRemoteApi) and the local DB is AppDatabase.forTesting().
Future<void> _seedConfig(AppDatabase db) async {
  // Direct insert to bypass updateConfig() which auto-creates sync queue entries
  await db.into(db.securityConfig).insert(
    SecurityConfigCompanion.insert(
      currentDeviceId: 'test-device-001',
      lastRealtimeEventId: Value(0),
    ),
  );
}

/// Seeds a minimal school + teacher + subject + one scheme_of_work row
/// (with the given [schemeServerId]) and returns the scheme row's local id.
Future<int> _seedSchemeRow(
  AppDatabase db, {
  required String schemeServerId,
}) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000101'),
          schoolName: 'Test School',
          shortCode: 'TS101',
          subscriptionTier: const Value('free'),
        ),
      );

  final teacherId = await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000201'),
          email: 'teacher@testschool.local',
          teacherName: 'Test Teacher',
          role: Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000101'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );

  final subjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-000000000301',
    name: 'Mathematics',
    schoolId: '00000000-0000-0000-0000-000000000101',
    sortOrder: 1,
  );

  return db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          serverId: Value(schemeServerId),
          schoolId: Value(schoolId),
          teacherId: Value(teacherId),
          subjectId: Value(subjectId),
          term: const Value('First'),
          weekNumber: const Value(1),
          topic: const Value('Algebraic Expressions'),
          objectives: const Value('Understand variables'),
          status: const Value('draft'),
          classLevel: const Value('JSS 1'),
        ),
      );
}

/// Seeds a lesson row with the given [serverId] (nullable for fresh rows)
/// and returns its local id.
Future<int> _seedLesson(
  AppDatabase db, {
  String? serverId,
}) {
  return db.into(db.lessons).insert(
        LessonsCompanion.insert(
          serverId: serverId != null ? Value(serverId) : const Value.absent(),
          subject: 'Mathematics',
          classLevel: 'JSS 1',
          week: 1,
          topic: 'Local lesson',
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

SyncService _buildService(
  AppDatabase db,
  FakeSyncRemoteApi remote,
  FakeSyncRecordStore store,
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

  group('sync-push server_id injection (UPDATE/DELETE)', () {
    test(
      'injects server_id into a scheme_of_work UPDATE payload that lacks it',
      () async {
        final schemeId = await _seedSchemeRow(
          db,
          schemeServerId: 'sow-uuid-0001',
        );
        // The admin-approve / submit-for-approval queue sites craft UPDATE
        // payloads WITHOUT server_id (see scheme_of_work_service.dart and
        // scheme_of_work_screen.dart). This is exactly what used to make the
        // server reject the entry with "missing server_id" and retry forever.
        await db.syncQueueDao.insertEntry(
          queueTable: 'scheme_of_work',
          recordLocalId: schemeId,
          operation: 'UPDATE',
          payload: {
            'topic': 'Updated topic',
            'status': 'approved',
          },
        );

        final remote = FakeSyncRemoteApi();
        await _buildService(db, remote, store).onConnectivityRestored();

        expect(remote.pushCalls, isNotEmpty);
        final batch = remote.pushCalls.first
            .singleWhere((b) => b.table == 'scheme_of_work');
        expect(batch.operation, 'UPDATE');
        final payload = PayloadCompressor.decompress(batch.record);
        expect(payload['server_id'], 'sow-uuid-0001',
            reason: 'server_id must be resolved from the local scheme row');
      },
    );

    test('injects server_id into a lessons UPDATE payload that lacks it',
        () async {
      final lessonId = await _seedLesson(db, serverId: 'lesson-uuid-0002');
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: lessonId,
        operation: 'UPDATE',
        payload: {
          'topic': 'Edited topic',
        },
      );

      final remote = FakeSyncRemoteApi();
      await _buildService(db, remote, store).onConnectivityRestored();

      final batch =
          remote.pushCalls.first.singleWhere((b) => b.table == 'lessons');
      expect(batch.operation, 'UPDATE');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload['server_id'], 'lesson-uuid-0002');
    });

    test('injects server_id into a DELETE payload that lacks it', () async {
      final lessonId = await _seedLesson(db, serverId: 'lesson-uuid-0003');
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: lessonId,
        operation: 'DELETE',
        payload: {
          'id': lessonId,
        },
      );

      final remote = FakeSyncRemoteApi();
      await _buildService(db, remote, store).onConnectivityRestored();

      final batch =
          remote.pushCalls.first.singleWhere((b) => b.table == 'lessons');
      expect(batch.operation, 'DELETE');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload['server_id'], 'lesson-uuid-0003');
    });

    test('does not overwrite a server_id already present in the payload',
        () async {
      final lessonId =
          await _seedLesson(db, serverId: 'local-row-uuid-0004');
      // A caller that deliberately includes server_id (e.g. the schools
      // queue site in auth_provider.dart) must keep its own value — the
      // local row's serverId must NOT win.
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: lessonId,
        operation: 'UPDATE',
        payload: {
          'topic': 'Edited topic',
          'server_id': 'payload-provided-uuid-0004',
        },
      );

      final remote = FakeSyncRemoteApi();
      await _buildService(db, remote, store).onConnectivityRestored();

      final batch =
          remote.pushCalls.first.singleWhere((b) => b.table == 'lessons');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload['server_id'], 'payload-provided-uuid-0004');
    });

    test('does not inject server_id for INSERT operations', () async {
      // A brand-new lesson has no server_id locally, so the stale-INSERT
      // recovery path must not fire and the new injection block must not
      // apply to INSERTs at all.
      final lessonId = await _seedLesson(db, serverId: null);
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: lessonId,
        operation: 'INSERT',
        payload: {
          'topic': 'Brand new lesson',
        },
      );

      final remote = FakeSyncRemoteApi();
      await _buildService(db, remote, store).onConnectivityRestored();

      final batch =
          remote.pushCalls.first.singleWhere((b) => b.table == 'lessons');
      expect(batch.operation, 'INSERT');
      final payload = PayloadCompressor.decompress(batch.record);
      expect(payload.containsKey('server_id'), isFalse);
    });
  });

  group('client UPDATE payload never sends updated_at (server bump guard)', () {
    test('scheme_of_work UPDATE entries queued by saveScheme omit updated_at',
        () async {
      // Seed school/teacher/subject with server ids so the service queues
      // sync entries (queueing is guarded on subjectServerId != null).
      final schoolId = await db.into(db.schools).insert(
            SchoolsCompanion.insert(
              serverId: const Value('00000000-0000-0000-0000-000000000501'),
              schoolName: 'Test School',
              shortCode: 'TS501',
              subscriptionTier: const Value('free'),
            ),
          );
      final teacherId = await db.into(db.teachers).insert(
            TeachersCompanion.insert(
              serverId: const Value('00000000-0000-0000-0000-000000000601'),
              email: 'teacher@testschool.local',
              teacherName: 'Test Teacher',
              role: Value('teacher'),
              schoolLocalId: schoolId,
              schoolServerId:
                  const Value('00000000-0000-0000-0000-000000000501'),
              isActive: const Value(true),
              forcePasswordReset: const Value(false),
              passwordHashVersion: const Value(1),
              themeMode: const Value('system'),
            ),
          );
      await db.subjectsDao.insert(
        serverId: '00000000-0000-0000-0000-000000000701',
        name: 'Mathematics',
        schoolId: '00000000-0000-0000-0000-000000000501',
        sortOrder: 1,
      );

      final service = SchemeOfWorkService(db);
      const weeks = [
        {'week': 1, 'topic': 'Algebraic Expressions', 'objectives': 'x'},
        {'week': 2, 'topic': 'Linear Equations', 'objectives': 'y'},
      ];

      // First pass creates the rows (INSERT entries).
      final weekIds = await service.saveScheme(
        schoolId: schoolId,
        teacherId: teacherId,
        subject: 'Mathematics',
        classLevel: 'JSS 1',
        term: 'First',
        weeks: weeks,
      );

      // Second pass with existingWeekRecordIds hits the UPDATE queue site.
      await service.saveScheme(
        schoolId: schoolId,
        teacherId: teacherId,
        subject: 'Mathematics',
        classLevel: 'JSS 1',
        term: 'First',
        weeks: weeks,
        existingWeekRecordIds: weekIds,
      );

      final updateRows = await (db.select(db.syncQueue)
            ..where((t) =>
                t.queueTable.equals('scheme_of_work') &
                t.operation.equals('UPDATE')))
          .get();

      expect(updateRows, isNotEmpty,
          reason: 'Expected scheme_of_work UPDATE queue entries');
      for (final row in updateRows) {
        final payload = _decodePayload(row.payload);
        expect(payload.containsKey('updated_at'), isFalse,
            reason:
                'Client UPDATE payloads must leave updated_at to the server '
                'so sync-push bumps it and peers re-pull the row');
        // Also confirms the premise of the server_id injection fix: the
        // queued payload has no server_id either.
        expect(payload.containsKey('server_id'), isFalse);
      }
    });
  });
}
