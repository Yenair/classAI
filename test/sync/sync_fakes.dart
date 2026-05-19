import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/core/services/sync_service.dart';
import 'package:crypto/crypto.dart';

class FakeSyncRecordStore implements SyncRecordStore {
  final AppDatabase db;
  final Map<String, Map<int, Map<String, dynamic>>> localRecords = {};
  final Map<String, Map<int, Map<String, dynamic>>> syncedRecords = {};
  final Map<String, Map<int, Map<String, dynamic>>> baseRecords = {};
  final List<Map<String, dynamic>> savedConflicts = [];

  FakeSyncRecordStore(this.db);

  void seedLocalRecord(String tableName, int localId, Map<String, dynamic> record) {
    localRecords.putIfAbsent(tableName, () => {});
    localRecords[tableName]![localId] = Map<String, dynamic>.from(record);
  }

  void seedBaseRecord({
    required String tableName,
    required int localId,
    required Map<String, dynamic> record,
  }) {
    final snapshotJson = jsonEncode(record);
    final hash = sha256.convert(utf8.encode(snapshotJson)).toString();
    baseRecords.putIfAbsent(tableName, () => {});
    baseRecords[tableName]![localId] = {
      'hash': hash,
      'record': Map<String, dynamic>.from(record),
    };
  }

  Future<void> seedVersionHashRow({
    required String tableName,
    required int localId,
  }) async {
    final seeded = baseRecords[tableName]?[localId];
    if (seeded == null) return;
    await db.into(db.versionHashes).insert(
      VersionHashesCompanion.insert(
        table: tableName,
        recordLocalId: localId,
        hash: seeded['hash'] as String,
        snapshotJson: Value(jsonEncode(seeded['record'])),
        setAt: DateTime.now(),
      ),
    );
  }

  String? baseHashFor(String tableName, int localId) {
    return baseRecords[tableName]?[localId]?['hash'] as String?;
  }

  @override
  Future<Map<String, dynamic>?> loadLocalRecord(String tableName, int localId) async {
    return localRecords[tableName]?[localId];
  }

  @override
  Future<Map<String, dynamic>?> loadBaseRecordByHash(
    String tableName,
    int localId,
    String? hash,
  ) async {
    if (hash == null) return null;
    final seeded = baseRecords[tableName]?[localId];
    if (seeded == null) return null;
    if (seeded['hash'] != hash) return null;
    return Map<String, dynamic>.from(seeded['record'] as Map);
  }

  @override
  Future<void> saveSyncedRecord({
    required String tableName,
    required int localId,
    required Map<String, dynamic> snapshot,
  }) async {
    syncedRecords.putIfAbsent(tableName, () => {});
    syncedRecords[tableName]![localId] = Map<String, dynamic>.from(snapshot);
    seedLocalRecord(tableName, localId, snapshot);
  }

  @override
  Future<void> saveConflict({
    required String recordType,
    required int recordLocalId,
    required List<String> conflictingFields,
    required String resolution,
    required bool notified,
  }) async {
    savedConflicts.add({
      'recordType': recordType,
      'recordLocalId': recordLocalId,
      'conflictingFields': conflictingFields,
      'resolution': resolution,
      'notified': notified,
    });
  }

  @override
  Future<List<SyncQueueData>> loadPendingQueue() {
    return db.syncQueueDao.pendingEntries();
  }

  @override
  Future<void> markQueueAttempt(int queueId, {DateTime? attemptedAt}) {
    return db.syncQueueDao.incrementAttempts(queueId, lastAttemptAt: attemptedAt);
  }

  @override
  Future<void> removeQueueEntry(int queueId) {
    return db.syncQueueDao.deleteById(queueId);
  }

  @override
  Future<SecurityConfigData> loadSecurityConfig() {
    return db.securityConfigDao.get();
  }

  @override
  Future<void> updateSecurityConfig({
    DateTime? lastPullTimestamp,
    String? syncCursor,
    DateTime? lastSyncAttemptTime,
    DateTime? syncCooldownUntil,
    int? lastRealtimeEventId,
  }) {
    return db.securityConfigDao.updateConfig(
      lastPullTimestamp: lastPullTimestamp,
      syncCursor: syncCursor,
      lastSyncAttemptTime: lastSyncAttemptTime,
      syncCooldownUntil: syncCooldownUntil,
      lastRealtimeEventId: lastRealtimeEventId,
    );
  }
}

class FakeSyncRemoteApi implements SyncRemoteApi {
  final List<SyncPullPage> pullPages;
  final List<SyncPushResponse> pushResponses;
  final List<SyncRealtimePage> realtimePages;

  final List<List<SyncPushBatch>> pushCalls = [];
  final List<Map<String, Object?>> pullCalls = [];
  final List<Map<String, Object?>> realtimeCalls = [];

  int _pullIndex = 0;
  int _pushIndex = 0;
  int _realtimeIndex = 0;

  FakeSyncRemoteApi({
    this.pullPages = const [],
    this.pushResponses = const [],
    this.realtimePages = const [],
  });

  @override
  Future<SyncPullPage> pullChanges({
    required String schoolId,
    String? cursor,
    int limit = 50,
  }) async {
    pullCalls.add({'schoolId': schoolId, 'cursor': cursor, 'limit': limit});
    if (_pullIndex < pullPages.length) {
      return pullPages[_pullIndex++];
    }
    return const SyncPullPage(changes: [], nextCursor: null);
  }

  @override
  Future<SyncPushResponse> pushChanges({
    required List<SyncPushBatch> batches,
    required String deviceId,
  }) async {
    pushCalls.add(List<SyncPushBatch>.from(batches));
    if (_pushIndex < pushResponses.length) {
      return pushResponses[_pushIndex++];
    }
    return SyncPushResponse(
      results: batches
          .map(
            (batch) => SyncPushResult(
              localId: _localIdFromBatch(batch),
              status: 'updated',
              serverId: null,
              retryable: false,
            ),
          )
          .toList(),
    );
  }

  @override
  Future<SyncRealtimePage> replayRealtimeEvents({
    required String schoolId,
    required int sinceEventId,
  }) async {
    realtimeCalls.add({
      'schoolId': schoolId,
      'sinceEventId': sinceEventId,
    });
    if (_realtimeIndex < realtimePages.length) {
      return realtimePages[_realtimeIndex++];
    }
    return const SyncRealtimePage(events: [], latestEventId: 0);
  }

  int _localIdFromBatch(SyncPushBatch batch) {
    final value = batch.record['local_id'] ?? batch.record['localId'] ?? batch.record['id'];
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }
}

class TrackingSecurityService extends SecurityService {
  bool clearSessionKeyCalled = false;
  bool authenticateCalled = false;
  bool authenticateResult = true;

  @override
  Future<bool> authenticateWithBiometric({required int timeoutSeconds}) async {
    authenticateCalled = true;
    return authenticateResult;
  }

  @override
  Future<void> clearSessionKey() async {
    clearSessionKeyCalled = true;
  }
}
