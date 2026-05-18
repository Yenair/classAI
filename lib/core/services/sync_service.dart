import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/merge_engine.dart';
import 'package:classai/core/services/merge_strategies.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/core/utils/payload_compressor.dart';

enum SyncState {
  idle,
  acquiringSession,
  biometricPrompt,
  sessionKeyDecrypt,
  pulling,
  merging,
  savingConflicts,
  pushing,
  applyingCredits,
  emergencySave,
  forcedLogout,
  updatingMetadata,
  replayingRealtime,
  backoff,
}

class SyncChange {
  final String table;
  final Map<String, dynamic> row;

  const SyncChange({required this.table, required this.row});

  factory SyncChange.fromJson(Map<String, dynamic> json) {
    return SyncChange(
      table: json['table'] as String? ?? '',
      row: Map<String, dynamic>.from(
        json['row'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}

class SyncPullPage {
  final List<SyncChange> changes;
  final String? nextCursor;

  const SyncPullPage({required this.changes, required this.nextCursor});

  factory SyncPullPage.fromJson(Map<String, dynamic> json) {
    final rawChanges = (json['changes'] as List? ?? const []);
    return SyncPullPage(
      changes: rawChanges
          .map((item) => SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
    );
  }
}

class SyncPushBatch {
  final String table;
  final String operation;
  final Map<String, dynamic> record;

  const SyncPushBatch({
    required this.table,
    required this.operation,
    required this.record,
  });

  Map<String, dynamic> toJson() => {
        'table': table,
        'operation': operation,
        'record': record,
      };
}

class SyncPushResult {
  final int localId;
  final String status;
  final String? serverId;
  final bool retryable;

  const SyncPushResult({
    required this.localId,
    required this.status,
    required this.serverId,
    required this.retryable,
  });

  factory SyncPushResult.fromJson(Map<String, dynamic> json) {
    return SyncPushResult(
      localId: _readInt(json, 'local_id') ?? 0,
      status: json['status'] as String? ?? 'error',
      serverId: json['server_id'] as String?,
      retryable: json['retryable'] as bool? ?? false,
    );
  }
}

class SyncPushResponse {
  final List<SyncPushResult> results;

  const SyncPushResponse({required this.results});

  factory SyncPushResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = (json['results'] as List? ?? const []);
    return SyncPushResponse(
      results: rawResults
          .map((item) =>
              SyncPushResult.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
    );
  }
}

class SyncRealtimeEvent {
  final int eventId;
  final String table;
  final Map<String, dynamic> payload;

  const SyncRealtimeEvent({
    required this.eventId,
    required this.table,
    required this.payload,
  });

  factory SyncRealtimeEvent.fromJson(Map<String, dynamic> json) {
    return SyncRealtimeEvent(
      eventId: _readInt(json, 'event_id') ?? 0,
      table: json['table'] as String? ?? '',
      payload: Map<String, dynamic>.from(
        json['payload'] as Map? ?? const <String, dynamic>{},
      ),
    );
  }
}

class SyncRealtimePage {
  final List<SyncRealtimeEvent> events;
  final int latestEventId;

  const SyncRealtimePage({
    required this.events,
    required this.latestEventId,
  });

  factory SyncRealtimePage.fromJson(Map<String, dynamic> json) {
    final rawEvents = (json['events'] as List? ?? const []);
    return SyncRealtimePage(
      events: rawEvents
          .map((item) => SyncRealtimeEvent.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      latestEventId: _readInt(json, 'latest_event_id') ?? 0,
    );
  }
}

abstract class SyncRemoteApi {
  Future<SyncPullPage> pullChanges({
    required String schoolId,
    String? cursor,
    int limit,
  });

  Future<SyncPushResponse> pushChanges({
    required List<SyncPushBatch> batches,
    required String deviceId,
  });

  Future<SyncRealtimePage> replayRealtimeEvents({
    required String schoolId,
    required int sinceEventId,
  });
}

class SupabaseSyncRemoteApi implements SyncRemoteApi {
  final SupabaseClient client;
  final String schoolId;

  static const List<String> _syncableTables = [
    'subjects',
    'lessons',
    'exams',
    'progress_logs',
    'vault_items',
    'scheme_of_work',
  ];

  SupabaseSyncRemoteApi({required this.schoolId})
      : client = Supabase.instance.client;

  SupabaseSyncRemoteApi.withClient({required this.client, required this.schoolId});

  @override
  Future<SyncPullPage> pullChanges({
    required String schoolId,
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final response = await client.functions.invoke('sync-pull', body: {
        'lastSyncTimestamp': cursor ?? '',
        'tables': _syncableTables,
      });
      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        return SyncPullPage.fromJson(data);
      }
    } catch (e, stackTrace) {
      // Edge Function not deployed or call failed — log and fall through.
      // The sync loop (_pullChanges) relies on empty pages as a graceful
      // fallback; throwing here would abort the entire sync cycle.
      debugPrint('SupabaseSyncRemoteApi.pullChanges failed: $e');
      await Sentry.captureException(
        e,
        stackTrace: stackTrace,
      );
    }

    // Edge Function call failed; return an empty page so the sync cycle
    // can continue without crashing.
    return const SyncPullPage(changes: [], nextCursor: null);
  }

  @override
  Future<SyncPushResponse> pushChanges({
    required List<SyncPushBatch> batches,
    required String deviceId,
  }) async {
    try {
      final response = await client.functions.invoke('sync-push', body: {
        'changes': batches.map((b) => {
          'table': b.table,
          'operation': b.operation,
          'rowData': b.record,
        }).toList(),
      });
      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        final success = data['success'] as bool? ?? false;
        final processed = data['processed'] as int? ?? 0;
        // Build SyncPushResponse from the simplified response.
        // Each entry is treated as "processed" — per-entry results
        // are not available with the new contract.
        return SyncPushResponse(
          results: batches.asMap().entries.map((entry) {
            final idx = entry.key;
            final batch = entry.value;
            final localId = _readInt(batch.record, 'localId') ??
                _readInt(batch.record, 'local_id') ??
                _readInt(batch.record, 'id') ??
                idx;
            return SyncPushResult(
              localId: localId,
              status: idx < processed ? 'updated' : 'error',
              serverId: batch.record['server_id'] as String? ??
                  batch.record['serverId'] as String?,
              retryable: !success,
            );
          }).toList(),
        );
      }
    } catch (e) {
      // Edge Function not deployed — log and fall through
      await Sentry.captureException(
        e,
        hint: null,
      );
    }

    // Edge Function call failed; return an error response so the sync
    // cycle can mark entries for retry.
    return SyncPushResponse(
      results: batches.map((b) {
        final localId = _readInt(b.record, 'localId') ??
            _readInt(b.record, 'local_id') ??
            _readInt(b.record, 'id') ??
            0;
        return SyncPushResult(
          localId: localId,
          status: 'error',
          serverId: null,
          retryable: true,
        );
      }).toList(),
    );
  }

  @override
  Future<SyncRealtimePage> replayRealtimeEvents({
    required String schoolId,
    required int sinceEventId,
  }) async {
    try {
      final response = await client.functions.invoke('sync-realtime-events', body: {
        'since_event_id': sinceEventId,
        'school_id': schoolId,
      });
      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        // Try to parse the response as a real SyncRealtimePage.
        // When the Edge Function is properly deployed, this will return
        // actual events. Until then, data will only contain { ok: true }
        // which will result in an empty page from SyncRealtimePage.fromJson().
        return SyncRealtimePage.fromJson(data);
      }
    } catch (e) {
      // Edge Function not deployed or call failed — log and fall through.
      // The pull-based sync cycle (SyncService._pullChanges()) serves as
      // a fallback to catch up on missed changes when the realtime endpoint
      // is unavailable.
      // ignore: avoid_print
      print('[sync] sync-realtime-events call failed: $e');
    }

    // Edge Function call failed; return empty page so the sync cycle
    // can continue without crashing. The next periodic pull cycle will
    // pick up any missed changes.
    return SyncRealtimePage(events: [], latestEventId: sinceEventId);
  }
}

abstract class SyncRecordStore {
  Future<Map<String, dynamic>?> loadLocalRecord(String tableName, int localId);

  Future<Map<String, dynamic>?> loadBaseRecordByHash(
    String tableName,
    int localId,
    String? hash,
  );

  Future<void> saveSyncedRecord({
    required String tableName,
    required int localId,
    required Map<String, dynamic> snapshot,
  });

  Future<void> saveConflict({
    required String recordType,
    required int recordLocalId,
    required List<String> conflictingFields,
    required String resolution,
    required bool notified,
  });

  Future<List<SyncQueueData>> loadPendingQueue();

  Future<void> markQueueAttempt(int queueId, {DateTime? attemptedAt});

  Future<void> removeQueueEntry(int queueId);

  Future<SecurityConfigData> loadSecurityConfig();

  Future<void> updateSecurityConfig({
    DateTime? lastPullTimestamp,
    String? syncCursor,
    DateTime? lastSyncAttemptTime,
    DateTime? syncCooldownUntil,
    int? lastRealtimeEventId,
  });
}

class DriftSyncRecordStore implements SyncRecordStore {
  final AppDatabase db;

  DriftSyncRecordStore(this.db);

  @override
  Future<Map<String, dynamic>?> loadLocalRecord(String tableName, int localId) {
    return _loadSnapshot(tableName, localId);
  }

  @override
  Future<Map<String, dynamic>?> loadBaseRecordByHash(
    String tableName,
    int localId,
    String? hash,
  ) async {
    if (hash == null) return null;
    final row = await (db.select(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) &
              t.recordLocalId.equals(localId) &
              t.hash.equals(hash)))
        .getSingleOrNull();
    return _decodeSnapshot(row?.snapshotJson);
  }

  @override
  Future<void> saveSyncedRecord({
    required String tableName,
    required int localId,
    required Map<String, dynamic> snapshot,
  }) async {
    final snapshotJson = jsonEncode(snapshot);
    final hash = _hashSnapshot(snapshotJson);
    await (db.delete(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) &
              t.recordLocalId.equals(localId)))
        .go();
    await db.into(db.versionHashes).insert(
          VersionHashesCompanion.insert(
            table: tableName,
            recordLocalId: localId,
            hash: hash,
            snapshotJson: Value(snapshotJson),
            setAt: DateTime.now(),
          ),
        );
  }

  @override
  Future<void> saveConflict({
    required String recordType,
    required int recordLocalId,
    required List<String> conflictingFields,
    required String resolution,
    required bool notified,
  }) async {
    final now = DateTime.now();
    await db.into(db.conflicts).insert(
          ConflictsCompanion.insert(
            recordType: recordType,
            recordLocalId: recordLocalId,
            conflictingFields: jsonEncode(conflictingFields),
            resolution: Value(resolution),
            notified: Value(notified),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  @override
  Future<List<SyncQueueData>> loadPendingQueue() {
    return db.syncQueueDao.pendingEntries();
  }

  @override
  Future<void> markQueueAttempt(int queueId, {DateTime? attemptedAt}) {
    return db.syncQueueDao.incrementAttempts(
      queueId,
      lastAttemptAt: attemptedAt,
    );
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

  Future<Map<String, dynamic>?> _loadSnapshot(String tableName, int localId) async {
    final row = await (db.select(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) & t.recordLocalId.equals(localId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.setAt, mode: OrderingMode.desc),
          ]))
        .getSingleOrNull();
    return _decodeSnapshot(row?.snapshotJson);
  }

  Map<String, dynamic>? _decodeSnapshot(String? snapshotJson) {
    if (snapshotJson == null || snapshotJson.isEmpty) return null;
    final decoded = jsonDecode(snapshotJson);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return null;
  }

  String _hashSnapshot(String snapshotJson) {
    return sha256.convert(utf8.encode(snapshotJson)).toString();
  }
}

class SyncService {
  final AppDatabase db;
  final String schoolId;
  final SecurityService securityService;
  final SyncRemoteApi remoteApi;
  final SyncRecordStore store;
  final MergeEngine mergeEngine;
  final Duration biometricTimeout;

  bool isForeground;
  bool biometricAvailable;
  bool sessionKeyValid;
  bool accountActive;

  SyncState _state = SyncState.idle;
  final List<SyncState> stateHistory = [SyncState.idle];

  SyncService({
    required this.db,
    required this.schoolId,
    required this.securityService,
    required this.remoteApi,
    SyncRecordStore? store,
    MergeEngine? mergeEngine,
    this.biometricTimeout = const Duration(seconds: 15),
    this.isForeground = true,
    this.biometricAvailable = true,
    this.sessionKeyValid = false,
    this.accountActive = true,
  })  : store = store ?? DriftSyncRecordStore(db),
        mergeEngine = mergeEngine ?? MergeEngine();

  SyncState get state => _state;

  Future<void> onConnectivityRestored() async {
    final config = await store.loadSecurityConfig();
    if (_cooldownActive(config.syncCooldownUntil)) {
      return;
    }

    _setState(SyncState.acquiringSession);
    await _acquireSession();
  }

  Future<void> _acquireSession() async {
    if (isForeground) {
      if (biometricAvailable) {
        _setState(SyncState.biometricPrompt);
        final success = await securityService.authenticateWithBiometric(
          timeoutSeconds: biometricTimeout.inSeconds,
        );
        if (!success) {
          await store.updateSecurityConfig(
            syncCooldownUntil: DateTime.now().add(const Duration(minutes: 5)),
            lastSyncAttemptTime: DateTime.now(),
          );
          _setState(SyncState.idle);
          return;
        }
      } else if (!sessionKeyValid) {
        _setState(SyncState.idle);
        return;
      }
    } else {
      if (!sessionKeyValid) {
        _setState(SyncState.idle);
        return;
      }
      _setState(SyncState.sessionKeyDecrypt);
    }

    await _pullChanges();
  }

  Future<void> _pullChanges() async {
    _setState(SyncState.pulling);
    final config = await store.loadSecurityConfig();
    String? cursor = config.syncCursor;

    while (true) {
      final page = await remoteApi.pullChanges(
        schoolId: schoolId,
        cursor: cursor,
        limit: 50,
      );

      for (final change in page.changes) {
        await _mergeRemoteChange(change);
      }

      cursor = page.nextCursor;
      await store.updateSecurityConfig(
        lastPullTimestamp: DateTime.now(),
        syncCursor: cursor,
        lastSyncAttemptTime: DateTime.now(),
      );

      if (cursor == null) {
        break;
      }
    }

    _setState(SyncState.pushing);
    await _pushChanges();
    _setState(SyncState.applyingCredits);
    await _applyCreditState();
  }

  Future<MergeResult> _threeWayMerge(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    String? baseHash,
    String tableName,
  ) async {
    final localId = _readInt(local, 'localId') ??
        _readInt(local, 'local_id') ??
        _readInt(local, 'id') ??
        _readInt(remote, 'localId') ??
        _readInt(remote, 'local_id') ??
        _readInt(remote, 'id') ??
        0;
    final base = await store.loadBaseRecordByHash(tableName, localId, baseHash);
    return mergeEngine.merge(
      local: local,
      remote: remote,
      base: base,
      tableName: tableName,
      fieldStrategies: mergeStrategiesForTable(tableName),
    );
  }

  Future<void> _pushChanges() async {
    final pending = await store.loadPendingQueue();
    if (pending.isEmpty) {
      return;
    }

    final sorted = [...pending]..sort(_compareQueueEntries);
    final batches = <SyncPushBatch>[];
    final config = await store.loadSecurityConfig();

    for (final entry in sorted) {
      final payload = _decodePayload(entry.payload);
      // Compress payload for 2G/3G optimization before pushing.
      final compressed = PayloadCompressor.compress(payload);
      batches.add(
        SyncPushBatch(
          table: entry.queueTable,
          operation: entry.operation,
          record: compressed,
        ),
      );
    }

    final response = await remoteApi.pushChanges(
      batches: batches,
      deviceId: config.currentDeviceId,
    );

    final resultsByLocalId = {
      for (final result in response.results) result.localId: result,
    };

    for (final entry in sorted) {
      final result = resultsByLocalId[entry.recordLocalId];
      if (result == null) {
        await store.markQueueAttempt(entry.id);
        continue;
      }

      if (result.status == 'created' ||
          result.status == 'updated' ||
          result.status == 'deleted') {
        await store.removeQueueEntry(entry.id);
        continue;
      }

      await store.markQueueAttempt(entry.id);
      if (result.retryable && entry.attempts < 5) {
        _setState(SyncState.backoff);
      }
    }
  }

  Future<void> _applyCreditState() async {
    final now = DateTime.now();
    if (!accountActive) {
      _setState(SyncState.emergencySave);
      await securityService.clearSessionKey();
      await (db.delete(db.syncQueue)..where((t) => t.isEmergency.equals(false))).go();
      _setState(SyncState.forcedLogout);
      _setState(SyncState.idle);
      return;
    }

    _setState(SyncState.updatingMetadata);
    await store.updateSecurityConfig(
      lastSyncAttemptTime: now,
      lastPullTimestamp: now,
      syncCooldownUntil: null,
    );

    _setState(SyncState.replayingRealtime);
    final config = await store.loadSecurityConfig();
    await _replayRealtimeEvents(config.lastRealtimeEventId);
    _setState(SyncState.idle);
  }

  Future<void> _replayRealtimeEvents(int lastEventId) async {
    final page = await remoteApi.replayRealtimeEvents(
      schoolId: schoolId,
      sinceEventId: lastEventId,
    );

    var latestEventId = lastEventId;
    for (final event in page.events) {
      if (event.eventId <= lastEventId) {
        continue;
      }
      latestEventId = event.eventId > latestEventId ? event.eventId : latestEventId;
      await _handleRealtimeEvent(event);
    }

    await store.updateSecurityConfig(lastRealtimeEventId: latestEventId);
  }

  Future<void> _handleRealtimeEvent(SyncRealtimeEvent event) async {
    final recordId =
        _readInt(event.payload, 'localId') ??
        _readInt(event.payload, 'local_id') ??
        _readInt(event.payload, 'id');
    if (recordId == null) {
      return;
    }

    await store.saveSyncedRecord(
      tableName: event.table,
      localId: recordId,
      snapshot: event.payload,
    );
  }

  Future<void> _mergeRemoteChange(SyncChange change) async {
    // Decompress the pulled change if it was compressed for 2G/3G optimization.
    final decompressed = PayloadCompressor.decompress(change.row);
    final remote = _normalizeRecord(decompressed);
    final localId = _readInt(remote, 'localId') ??
        _readInt(remote, 'local_id') ??
        _readInt(remote, 'id') ??
        0;
    final local = await store.loadLocalRecord(change.table, localId) ?? const {};
    final baseHash = await _loadBaseHash(change.table, localId);
    final result = await _threeWayMerge(local, remote, baseHash, change.table);

    if (baseHash == null) {
      _setState(SyncState.savingConflicts);
      await store.saveConflict(
        recordType: change.table,
        recordLocalId: localId,
        conflictingFields: local.keys.toList(),
        resolution: MergeResolution.remote.name,
        notified: false,
      );
    } else if (result.conflictingFields.isNotEmpty) {
      _setState(SyncState.savingConflicts);
      await store.saveConflict(
        recordType: change.table,
        recordLocalId: localId,
        conflictingFields: result.conflictingFields,
        resolution: result.resolution.name,
        notified: false,
      );
    }

    await store.saveSyncedRecord(
      tableName: change.table,
      localId: localId,
      snapshot: result.merged,
    );
    _setState(SyncState.merging);
  }

  Future<String?> _loadBaseHash(String tableName, int localId) async {
    final row = await (db.select(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) & t.recordLocalId.equals(localId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.setAt, mode: OrderingMode.desc),
          ]))
        .getSingleOrNull();
    return row?.hash;
  }

  Map<String, dynamic> _decodePayload(String payload) {
    if (payload.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(payload);
    if (decoded is Map) {
      return Map<String, dynamic>.from(decoded);
    }
    return <String, dynamic>{};
  }

  Map<String, dynamic> _normalizeRecord(Map<String, dynamic> record) {
    final normalized = Map<String, dynamic>.from(record);
    if (normalized.containsKey('id') && !normalized.containsKey('localId')) {
      normalized['localId'] = normalized['id'];
    }
    return normalized;
  }

  bool _cooldownActive(DateTime? cooldownUntil) {
    if (cooldownUntil == null) return false;
    return cooldownUntil.isAfter(DateTime.now());
  }

  int _compareQueueEntries(SyncQueueData a, SyncQueueData b) {
    if (a.isEmergency != b.isEmergency) {
      return a.isEmergency ? -1 : 1;
    }

    final tableDiff = _tablePriority(a.queueTable).compareTo(
      _tablePriority(b.queueTable),
    );
    if (tableDiff != 0) return tableDiff;

    final opDiff = _operationPriority(a.operation).compareTo(
      _operationPriority(b.operation),
    );
    if (opDiff != 0) return opDiff;

    return a.createdAt.compareTo(b.createdAt);
  }

  int _tablePriority(String tableName) {
    switch (tableName) {
      case 'schools':
        return 0;
      case 'subjects':
        return 1;
      case 'lessons':
        return 2;
      case 'exams':
        return 3;
      case 'progress_logs':
        return 4;
      default:
        return 99;
    }
  }

  int _operationPriority(String operation) {
    switch (operation.toUpperCase()) {
      case 'INSERT':
        return 0;
      case 'UPDATE':
        return 1;
      case 'DELETE':
        return 2;
      case 'SPEND_CREDITS':
        return 3;
      default:
        return 99;
    }
  }

  void _setState(SyncState next) {
    _state = next;
    stateHistory.add(next);
  }
}

int? _readInt(Map<String, dynamic> map, String key) {
  final value = map[key];
  if (value is int) return value;
  if (value is String) return int.tryParse(value);
  return null;
}
