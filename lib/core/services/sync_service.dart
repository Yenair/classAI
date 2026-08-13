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
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:classai/core/utils/payload_compressor.dart';

/// Thrown when the server reports that the current session has been invalidated
/// by a login on another device (token_version_mismatch).
class SessionMismatchException implements Exception {
  final String message;
  const SessionMismatchException(
      [this.message = 'Session expired due to login on another device']);

  @override
  String toString() => 'SessionMismatchException: $message';
}

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

  /// Set of teacher server IDs that are active on the server.
  /// Used by [SyncService._reconcileTeacherRoster] to remove locally-stored
  /// teachers that were hard-deleted from the cloud (Issue 1).
  final Set<String>? activeTeacherIds;

  /// Teacher records with [force_password_reset] == true that may have been
  /// missed by the incremental pull because they weren't updated recently.
  /// These are upserted in [SyncService._pullChanges] after the main loop
  /// (Issue 3).
  final List<SyncChange>? pendingTeachers;

  /// Full school-scoped subject catalog returned by the server (id,
  /// subject_name, school_id, is_active, deleted_at), independent of the
  /// incremental cursor. Null when the pull failed (so the subject self-heal
  /// is skipped); a possibly-empty list when the pull succeeded but the
  /// school has no subjects.
  final List<Map<String, dynamic>>? subjectCatalog;

  /// Identity catalogs for the full-table reconciliation, keyed by table
  /// name ('lessons', 'exams', 'scheme_of_work', 'progress_logs'), each an
  /// array of minimal-column rows (see sync-pull CATALOG_PROJECTIONS).
  /// Independent of the incremental cursor; returned on every page. Null when
  /// the pull failed (so reconciliation is skipped); a possibly-empty map
  /// when the pull succeeded but the server did not return catalogs (older
  /// sync-pull — reconciliation degrades to a no-op).
  final Map<String, List<Map<String, dynamic>>>? tableCatalogs;

  const SyncPullPage({
    required this.changes,
    required this.nextCursor,
    this.activeTeacherIds,
    this.pendingTeachers,
    this.subjectCatalog,
    this.tableCatalogs,
  });

  factory SyncPullPage.fromJson(Map<String, dynamic> json) {
    final rawChanges = (json['changes'] as List? ?? const []);
    final rawPendingTeachers = (json['pending_teachers'] as List? ?? const []);
    return SyncPullPage(
      changes: rawChanges
          .map((item) =>
              SyncChange.fromJson(Map<String, dynamic>.from(item as Map)))
          .toList(),
      nextCursor: json['next_cursor'] as String?,
      activeTeacherIds: json['active_teacher_ids'] != null
          ? Set<String>.from(json['active_teacher_ids'] as List)
          : null,
      pendingTeachers: rawPendingTeachers.isNotEmpty
          ? rawPendingTeachers
              .map((item) => SyncChange(
                    table: 'teachers',
                    row: Map<String, dynamic>.from(item as Map),
                  ))
              .toList()
          : null,
      subjectCatalog: json['subject_catalog'] is List
          ? (json['subject_catalog'] as List)
              .map((item) =>
                  Map<String, dynamic>.from(item as Map))
              .toList()
          : null,
      tableCatalogs: json['catalogs'] is Map
          ? (json['catalogs'] as Map).map((key, value) => MapEntry(
                key as String,
                (value as List)
                    .map((item) =>
                        Map<String, dynamic>.from(item as Map))
                    .toList(),
              ))
          : null,
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
  final String? errorMessage;

  const SyncPushResult({
    required this.localId,
    required this.status,
    required this.serverId,
    required this.retryable,
    this.errorMessage,
  });

  factory SyncPushResult.fromJson(Map<String, dynamic> json) {
    final localIdValue = json['local_id'];
    final localId = localIdValue is num
        ? localIdValue.toInt()
        : int.tryParse(localIdValue?.toString() ?? '') ?? 0;
    final status = json['status']?.toString().trim();
    return SyncPushResult(
      localId: localId,
      status: status != null && status.isNotEmpty ? status : 'error',
      serverId: json['server_id']?.toString(),
      retryable: json['retryable'] as bool? ?? false,
      errorMessage: json['error']?.toString() ??
          json['error_message']?.toString() ??
          json['message']?.toString(),
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
          .map((item) => SyncRealtimeEvent.fromJson(
              Map<String, dynamic>.from(item as Map)))
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

  /// Fetches the current credit state from the server.
  /// Returns a map with 'offlineCredits', 'creditServerCounter', and 'spentIds'.
  Future<Map<String, dynamic>?> fetchCreditState();
}

class SupabaseSyncRemoteApi implements SyncRemoteApi {
  final SupabaseClient client;
  final String schoolId;
  String? _jwt;

  void setJwt(String? jwt) {
    _jwt = jwt;
  }

  static const List<String> _syncableTables = [
    'subjects',
    'lessons',
    'exams',
    'progress_logs',
    'vault_items',
    'scheme_of_work',
    'teachers',
    'schools',
    'payment_events',
  ];

  SupabaseSyncRemoteApi({required this.schoolId})
      : client = Supabase.instance.client;

  SupabaseSyncRemoteApi.withClient(
      {required this.client, required this.schoolId});

  @override
  Future<SyncPullPage> pullChanges({
    required String schoolId,
    String? cursor,
    int limit = 50,
  }) async {
    try {
      final headers = <String, String>{};
      if (_jwt != null && _jwt!.isNotEmpty) {
        headers['x-classai-jwt'] = _jwt!;
      }
      final response = await client.functions.invoke(
        'sync-pull',
        headers: headers.isNotEmpty ? headers : null,
        body: {
          'lastSyncTimestamp': cursor ?? '',
          'tables': _syncableTables,
          'school_id': schoolId,
          // Identity catalogs for the full-table reconciliation (Fix 5).
          'catalogs': ['lessons', 'exams', 'scheme_of_work', 'progress_logs'],
        },
      );
      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        return SyncPullPage.fromJson(data);
      }
    } on FunctionException catch (e) {
      if (e.status == 401) {
        final code =
            (e.details is Map) ? (e.details as Map)['code'] as String? : null;
        if (code == 'token_version_mismatch') {
          throw SessionMismatchException();
        }
      }
      // Other FunctionExceptions — log and fall through to empty page
      debugPrint('SupabaseSyncRemoteApi.pullChanges failed: $e');
      await Sentry.captureException(e);
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
    String? errorMessage;
    try {
      final headers = <String, String>{};
      if (_jwt != null && _jwt!.isNotEmpty) {
        headers['x-classai-jwt'] = _jwt!;
      }
      final response = await client.functions.invoke(
        'sync-push',
        headers: headers.isNotEmpty ? headers : null,
        body: {
          'changes': batches
              .map((b) => {
                    'table': b.table,
                    'operation': b.operation,
                    'rowData': b.record,
                  })
              .toList(),
        },
      );
      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        // DIAG: Log the raw server response to see what results we got back
        debugPrint('[PUSH-DIAG] Raw server response: $data');
        final rawResults = data['results'] as List? ?? [];
        // Parse per-entry results returned by the server, which include
        // the correct local_id, status, server_id, and retryable for each
        // change (including SPEND_CREDITS entries with status 'skipped').
        return SyncPushResponse(
          results: rawResults.map((item) {
            return SyncPushResult.fromJson(
              Map<String, dynamic>.from(item as Map),
            );
          }).toList(),
        );
      }
    } on FunctionException catch (e) {
      debugPrint('[PUSH-ERROR] FunctionException caught in pushChanges()');
      debugPrint('[PUSH-ERROR] Status: ${e.status}');
      debugPrint('[PUSH-ERROR] Details: ${e.details}');
      final details = e.details;
      errorMessage = details is Map
          ? (details['error']?.toString() ??
              details['message']?.toString() ??
              details['detail']?.toString())
          : null;
      if (e.status == 401) {
        final code =
            (e.details is Map) ? (e.details as Map)['code'] as String? : null;
        if (code == 'token_version_mismatch') {
          debugPrint('[PUSH-ERROR] Throwing SessionMismatchException');
          throw SessionMismatchException();
        }
      }
      // Other FunctionExceptions — log and fall through
      await Sentry.captureException(e);
    } catch (e, stackTrace) {
      debugPrint('[PUSH-ERROR] Exception caught in pushChanges(): $e');
      debugPrint('[PUSH-ERROR] Stack trace: $stackTrace');
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
          errorMessage: errorMessage,
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
      final headers = <String, String>{};
      if (_jwt != null && _jwt!.isNotEmpty) {
        headers['x-classai-jwt'] = _jwt!;
      }
      final response = await client.functions.invoke('sync-realtime-events',
          headers: headers.isNotEmpty ? headers : null,
          body: {
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
    } on FunctionException catch (e) {
      if (e.status == 401) {
        final code =
            (e.details is Map) ? (e.details as Map)['code'] as String? : null;
        if (code == 'token_version_mismatch') {
          throw SessionMismatchException();
        }
      }
      // Log and fall through
      // ignore: avoid_print
      print('[sync] sync-realtime-events call failed: $e');
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

  @override
  Future<Map<String, dynamic>?> fetchCreditState() async {
    try {
      final headers = <String, String>{};
      if (_jwt != null && _jwt!.isNotEmpty) {
        headers['x-classai-jwt'] = _jwt!;
      }
      final response = await client.functions.invoke(
        'sync-credits',
        headers: headers.isNotEmpty ? headers : null,
      );
      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        return {
          'offlineCredits': data['offline_credits'] as int? ?? 3,
          'creditServerCounter': data['credit_server_counter'] as int? ?? 0,
          'spentIds': data['spent_ids'] as String? ?? '[]',
        };
      }
    } catch (e) {
      debugPrint('fetchCreditState failed: $e');
    }
    return null;
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
    required String? localValue,
    required String? remoteValue,
    required String resolution,
    required bool notified,
  });

  Future<void> saveFieldConflictHistory({
    required String recordTable,
    required int recordLocalId,
    required String fieldName,
    required String discardedValueJson,
    required String winningValueJson,
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
  });

  Future<List<SyncQueueSnapshotData>> loadDeferredTeacherSnapshots();

  Future<void> saveDeferredTeacherSnapshot({
    required Map<String, dynamic> snapshot,
  });

  Future<void> removeDeferredTeacherSnapshot(int snapshotId);

  Future<List<SyncQueueData>> loadPendingQueue();

  Future<void> markQueueAttempt(
    int queueId, {
    DateTime? attemptedAt,
    DateTime? nextRetryAt,
  });

  Future<void> markQueueTerminalFailure(
    int queueId, {
    String? lastError,
    DateTime? failedAt,
  });

  /// One-time recovery for legacy terminal rows that were dropped only
  /// because a retryable failure exhausted the old 5-attempt cap. Resets the
  /// matching rows to pending and returns how many were reset (0 is a no-op).
  Future<int> recoverRetryableTerminalRows();

  Future<void> removeQueueEntry(int queueId);

  Future<void> clearVersionHashes();

  Future<SecurityConfigData> loadSecurityConfig();

  Future<void> updateSecurityConfig({
    DateTime? lastPullTimestamp,
    String? syncCursor,
    DateTime? lastSyncAttemptTime,
    DateTime? syncCooldownUntil,
    int? lastRealtimeEventId,
    bool clearCursor = false,
  });
}

class DriftSyncRecordStore implements SyncRecordStore {
  final AppDatabase db;

  DriftSyncRecordStore(this.db);

  @override
  Future<void> clearVersionHashes() async {
    await db.delete(db.versionHashes).go();
  }

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
              t.table.equals(tableName) & t.recordLocalId.equals(localId)))
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
    required String? localValue,
    required String? remoteValue,
    required String resolution,
    required bool notified,
  }) async {
    final now = DateTime.now();
    await db.into(db.conflicts).insert(
          ConflictsCompanion.insert(
            recordType: recordType,
            recordLocalId: recordLocalId,
            conflictingFields: jsonEncode(conflictingFields),
            localValue: Value(localValue),
            remoteValue: Value(remoteValue),
            resolution: Value(resolution),
            notified: Value(notified),
            createdAt: Value(now),
            updatedAt: Value(now),
          ),
        );
  }

  @override
  Future<void> saveFieldConflictHistory({
    required String recordTable,
    required int recordLocalId,
    required String fieldName,
    required String discardedValueJson,
    required String winningValueJson,
    required DateTime? localUpdatedAt,
    required DateTime? remoteUpdatedAt,
  }) async {
    await db.into(db.fieldConflictHistory).insert(
          FieldConflictHistoryCompanion.insert(
            recordTable: recordTable,
            recordLocalId: recordLocalId,
            fieldName: fieldName,
            discardedValueJson: discardedValueJson,
            winningValueJson: winningValueJson,
            localUpdatedAt: localUpdatedAt != null
                ? Value(localUpdatedAt)
                : const Value.absent(),
            remoteUpdatedAt: remoteUpdatedAt != null
                ? Value(remoteUpdatedAt)
                : const Value.absent(),
          ),
        );
  }

  @override
  Future<List<SyncQueueSnapshotData>> loadDeferredTeacherSnapshots() {
    return (db.select(db.syncQueueSnapshot)
          ..orderBy([
            (t) => OrderingTerm(expression: t.createdAt),
          ]))
        .get();
  }

  @override
  Future<void> saveDeferredTeacherSnapshot({
    required Map<String, dynamic> snapshot,
  }) async {
    await db.into(db.syncQueueSnapshot).insert(
          SyncQueueSnapshotCompanion.insert(
            snapshotData: jsonEncode(snapshot),
          ),
        );
  }

  @override
  Future<void> removeDeferredTeacherSnapshot(int snapshotId) {
    return (db.delete(db.syncQueueSnapshot)
          ..where((t) => t.id.equals(snapshotId)))
        .go();
  }

  @override
  Future<List<SyncQueueData>> loadPendingQueue() {
    return db.syncQueueDao.pendingEntries();
  }

  @override
  Future<void> markQueueAttempt(
    int queueId, {
    DateTime? attemptedAt,
    DateTime? nextRetryAt,
  }) {
    return db.syncQueueDao.incrementAttempts(
      queueId,
      lastAttemptAt: attemptedAt,
      nextRetryAt: nextRetryAt,
    );
  }

  @override
  Future<int> recoverRetryableTerminalRows() {
    return db.syncQueueDao.recoverRetryableTerminalRows();
  }

  @override
  Future<void> markQueueTerminalFailure(
    int queueId, {
    String? lastError,
    DateTime? failedAt,
  }) {
    return db.syncQueueDao.markTerminalFailure(
      queueId,
      lastError: lastError,
      failedAt: failedAt,
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
    bool clearCursor = false,
  }) {
    return db.securityConfigDao.updateConfig(
      lastPullTimestamp: lastPullTimestamp,
      syncCursor: clearCursor ? null : syncCursor,
      lastSyncAttemptTime: lastSyncAttemptTime,
      syncCooldownUntil: syncCooldownUntil,
      lastRealtimeEventId: lastRealtimeEventId,
    );
  }

  Future<Map<String, dynamic>?> _loadSnapshot(
      String tableName, int localId) async {
    final rows = await (db.select(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) & t.recordLocalId.equals(localId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.setAt, mode: OrderingMode.desc),
          ]))
        .get();
    final row = rows.isEmpty ? null : rows.first;
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
  /// One-shot guard: the legacy terminal-row recovery (rows dropped only
  /// because a retryable failure exhausted the old 5-attempt cap) runs once
  /// per process, on the first push cycle.
  static bool _legacyRetryRecoveryDone = false;

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

  /// Performs a full resync by first pushing any pending local changes,
  /// then clearing the sync cursor and all version hashes.
  /// This forces the next pull to fetch all records from the server and
  /// re-merge them locally, effectively recovering from a stuck sync state.
  ///
  /// Pending changes are pushed FIRST to ensure local edits are not lost
  /// when the version_hashes are cleared (which would cause the merge
  /// to default to "remote wins" with no base for comparison).
  ///
  /// Returns true if there are still pending entries after the push phase
  /// (indicating push failures that may result in data loss during the
  /// subsequent full pull).
  Future<bool> forceFullResync({String? jwt}) async {
    debugPrint('[SYNC] Initiating force full resync...');

    // 1. Push any pending changes FIRST to preserve local edits
    if (jwt != null && jwt.isNotEmpty && remoteApi is SupabaseSyncRemoteApi) {
      (remoteApi as SupabaseSyncRemoteApi).setJwt(jwt);
    }
    await _pushChanges();

    // Check if push left any pending entries (push failures)
    final pendingAfterPush = await store.loadPendingQueue();
    final hasPushFailures = pendingAfterPush.isNotEmpty;

    // 2. Clear version hashes
    await store.clearVersionHashes();
    // 3. Clear sync cursor
    await store.updateSecurityConfig(clearCursor: true);
    // 4. Trigger a sync cycle
    await onConnectivityRestored(jwt: jwt);
    debugPrint('[SYNC] Force full resync completed.');

    return hasPushFailures;
  }

  Future<void> onConnectivityRestored({String? jwt}) async {
    final config = await store.loadSecurityConfig();
    if (_cooldownActive(config.syncCooldownUntil)) {
      return;
    }

    // If a JWT is provided, set it on the remote API and run sync directly
    // bypassing the biometric/session gate. This is the normal path from
    // SyncStatusNotifier.syncNow() and _autoSync().
    if (jwt != null && jwt.isNotEmpty && remoteApi is SupabaseSyncRemoteApi) {
      (remoteApi as SupabaseSyncRemoteApi).setJwt(jwt);
      await _pullChanges();
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

  /// Performs a full sync cycle without biometric/session authentication.
  /// Used by the admin dashboard to pull teacher data on initial load
  /// without being blocked by the biometric gate.
  ///
  /// If [jwt] is provided, it will be set on the remote API for
  /// authenticated requests to the sync-pull edge function.
  ///
  /// If [overrideSchoolId] is provided, it overrides [schoolId] for this pull.
  /// This is needed when the local DB has a stale school record and the
  /// caller has the correct school serverId from auth state.
  Future<void> pullNow({String? jwt, String? overrideSchoolId}) async {
    if (jwt != null && jwt.isNotEmpty && remoteApi is SupabaseSyncRemoteApi) {
      (remoteApi as SupabaseSyncRemoteApi).setJwt(jwt);
    }
    final config = await store.loadSecurityConfig();
    // Clear any stale cooldown — pullNow is explicitly designed to bypass
    // biometric/session gates and should not be blocked by a cooldown that
    // was set by a previous biometric failure.
    if (config.syncCooldownUntil != null) {
      await store.updateSecurityConfig(syncCooldownUntil: null);
    }
    await _pullChanges(schoolIdOverride: overrideSchoolId);
    await db.reconcileLegacyTeachers();
  }

  Future<void> _pullChanges({String? schoolIdOverride}) async {
    // ── Push FIRST ────────────────────────────────────────────────────
    // Push local changes (INSERTs, UPDATEs, DELETEs) to the server before
    // pulling remote changes. This ensures that locally created rows with
    // serverId == null are uploaded first — the server returns the generated
    // serverId, which _pushChanges stores locally via _updateLocalServerId().
    // When the pull phase runs next, the upsert logic in _mergeRemoteChange
    // finds the matching serverId and UPDATES the row instead of INSERTing
    // a duplicate. See FIX A — pull-before-push ordering bug.
    _setState(SyncState.pushing);
    await _pushChanges();
    // ── Pull SECOND ───────────────────────────────────────────────────
    _setState(SyncState.pulling);

    // ── One-shot duplicate cleanup ──────────────────────────────────────
    // Previous buggy sync runs (before school_id was correctly passed to
    // the edge function) may have inserted duplicate teacher rows because
    // the Teachers table has no unique constraint on server_id. Clean up
    // any duplicates now: keep the row with the lowest localId for each
    // non-null serverId.
    await _deduplicateTeachers();
    // ────────────────────────────────────────────────────────────────────

    final config = await store.loadSecurityConfig();
    String? cursor = config.syncCursor;
    final effectiveSchoolId = schoolIdOverride ?? schoolId;

    // Collect reconciliation metadata across all pages (Issues 1 & 3)
    Set<String>? activeTeacherIds;
    List<SyncChange>? pendingTeachers;
    // Full subject catalog (returned on every page; captured from the last
    // page that carried one) for the subject self-heal reconciliation below.
    List<Map<String, dynamic>>? subjectCatalog;
    // Identity catalogs for the full-table reconciliation (same capture
    // semantics: last page that carried one).
    Map<String, List<Map<String, dynamic>>>? tableCatalogs;
    int totalTeacherChanges = 0;

    while (true) {
      final page = await remoteApi.pullChanges(
        schoolId: effectiveSchoolId,
        cursor: cursor,
        limit: 50,
      );

      debugPrint(
        '[SYNC-DEBUG] Pull page: schoolId=$effectiveSchoolId, cursor=$cursor, '
        'changes=${page.changes.length}, '
        'activeTeacherIds=${page.activeTeacherIds?.length ?? 0}, '
        'pendingTeachers=${page.pendingTeachers?.length ?? 0}',
      );

      // Log teacher changes specifically
      final teacherChanges =
          page.changes.where((c) => c.table == 'teachers').toList();
      if (teacherChanges.isNotEmpty) {
        debugPrint(
          '[SYNC-DEBUG] Teacher changes in this page: ${teacherChanges.length}',
        );
        for (final tc in teacherChanges) {
          debugPrint(
            '[SYNC-DEBUG]   Teacher: id=${tc.row['id']}, '
            'email=${tc.row['email']}, school_id=${tc.row['school_id']}',
          );
        }
      }

      // Log active teacher IDs
      if (page.activeTeacherIds != null && page.activeTeacherIds!.isNotEmpty) {
        debugPrint(
          '[SYNC-DEBUG] Active teacher IDs (first 5): '
          '${page.activeTeacherIds!.take(5).join(', ')}',
        );
      }

      // Track teacher changes to detect contradictory empty activeTeacherIds
      totalTeacherChanges += teacherChanges.length;

      for (final change in page.changes) {
        await _mergeRemoteChange(change);
      }

      // Capture metadata from each page (returned by the edge function
      // alongside the incremental changes).
      if (page.activeTeacherIds != null) {
        activeTeacherIds = page.activeTeacherIds;
      }
      if (page.pendingTeachers != null && page.pendingTeachers!.isNotEmpty) {
        pendingTeachers = page.pendingTeachers;
      }
      if (page.subjectCatalog != null) {
        subjectCatalog = page.subjectCatalog;
      }
      if (page.tableCatalogs != null) {
        tableCatalogs = page.tableCatalogs;
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

    debugPrint(
      '[SYNC-DEBUG] Final totals: pendingTeachers=${pendingTeachers?.length ?? 0}, '
      'activeTeacherIds=${activeTeacherIds?.length ?? 0}',
    );

    // ── Post-pull reconciliation ──────────────────────────────────────
    // Issue 1: Remove local teachers that were hard-deleted on the server
    // (they won't appear in the incremental pull since no change event is
    // generated for hard deletes).
    if (activeTeacherIds != null) {
      // Guard: An empty activeTeacherIds alongside real teacher changes in the
      // same pull is contradictory — the server is telling us "nobody is active"
      // while also sending us teacher records. This means the server-side
      // active_teacher_ids query failed or returned empty erroneously. Do NOT
      // trust an empty roster in this case; skip reconciliation and log.
      if (activeTeacherIds.isEmpty && totalTeacherChanges > 0) {
        debugPrint(
          '[SYNC] WARNING: activeTeacherIds is empty but $totalTeacherChanges '
          'teacher change(s) were processed in this pull. This is contradictory '
          '— skipping _reconcileTeacherRoster to avoid wrongly marking active '
          'teachers as deleted.',
        );
      } else {
        await _reconcileTeacherRoster(
          activeTeacherIds,
          schoolId: effectiveSchoolId,
        );
      }
    }

    // Issue 3: Upsert any pending (force_password_reset=true) teachers that
    // may have been missed by the incremental pull because their record was
    // last modified before the sync cursor.
    if (pendingTeachers != null) {
      for (final change in pendingTeachers) {
        await _upsertTeacherFromSync(change.row);
      }
    }

    // ── Subject self-heal ─────────────────────────────────────────────
    // Reconcile local subjects against the full server subject catalog so
    // subjects that never reached the server (or carry a stale server_id
    // from the old cross-table local_id collision) are healed permanently
    // and idempotently. Runs only when the pull succeeded (catalog present).
    if (subjectCatalog != null) {
      await _reconcileLocalSubjects(
        subjectCatalog!,
        effectiveSchoolId: effectiveSchoolId,
      );
    }

    // ── Full-table reconciliation ────────────────────────────────────────
    // Generalizes the subject self-heal to lessons, exams, scheme_of_work,
    // and progress_logs using the server-provided identity catalogs. Runs
    // only when the pull succeeded AND an active school is known (strict
    // school scoping — a null effectiveSchoolId skips everything). Rows are
    // matched by server id, then by natural key, then re-queued as clean
    // INSERTs when genuinely missing — with the stop-limit (Fix 6) and the
    // progress_logs one-shot (Fix 1) guarding against infinite re-queues.
    if (tableCatalogs != null && effectiveSchoolId.isNotEmpty) {
      await _reconcileMissingLocalRows(
        tableCatalogs!,
        effectiveSchoolId: effectiveSchoolId,
      );
      // Fix 7: surface over-threshold rows and last-cycle counts in the log.
      await debugDumpReconcileIssues();
    }

    // ── Permanent cooldown reset for existing server subjects ─────────────
    // Runs once per successful pull, after both reconciliation passes: clears
    // the stale retry cooldown on pending scheme_of_work / lessons / exams
    // entries whose subject already exists server-side, so dependents of
    // long-settled subjects (server_id present) become due for push instead
    // of sitting in cooldown forever. Idempotent; no-op when no entry is in
    // cooldown or no local subject has a server_id yet.
    await _resetCooldownsForExistingServerSubjects();

    await _flushDeferredTeachers();

    // Check subscription expiry using server time after a successful pull.
    await _checkSubscriptionExpiry();
    _setState(SyncState.applyingCredits);
    await _applyCreditState();
  }

  /// Calls the [server-time] edge function and checks whether the local
  /// school's [expiryDate] has passed. If so, downgrades the subscription
  /// to [free] so the UI shows the correct tier without waiting for the
  /// next auth refresh cycle.
  ///
  /// Uses the server-provided time — never [DateTime.now].
  Future<void> _checkSubscriptionExpiry() async {
    try {
      final client = Supabase.instance.client;
      final response = await client.functions
          .invoke('server-time')
          .timeout(const Duration(seconds: 10));
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return;
      final timeStr = data['server_time'] as String?;
      if (timeStr == null) return;
      final serverTime = DateTime.tryParse(timeStr);
      if (serverTime == null) return;

      // Use the configured schoolId passed into SyncService at construction,
      // not schoolsDao.get() which may return the wrong school when multiple
      // school records exist locally (no serverId filter, just limit(1)).
      final school = schoolId.isNotEmpty
          ? await db.schoolsDao.getByServerId(schoolId)
          : await db.schoolsDao.get();
      if (school == null) return;
      final expiry = school.expiryDate;
      if (expiry == null) return;

      if (expiry.isBefore(serverTime)) {
        debugPrint(
          '[SyncService] Subscription expired: expiry=$expiry, serverTime=$serverTime',
        );
        if (school.serverId != null) {
          await db.schoolsDao.updateSubscriptionFields(
            serverId: school.serverId!,
            subscriptionTier: 'free',
            expiryDate: null,
            activationCode: null,
          );
        }
      }
    } catch (e) {
      // Silently ignore — the next sync cycle will re-check.
      if (e.toString().contains('_instance._isInitialized')) {
        return;
      }
      debugPrint('[SyncService] Failed to check subscription expiry: $e');
    }
  }

  /// Removes locally-stored teachers whose [serverId] is not in the server's
  /// set of active teacher IDs. This handles the case where teachers were
  /// hard-deleted from Supabase SQL — the incremental sync-pull never returns
  /// a "delete" event for hard deletes, so we reconcile by comparing the
  /// full server roster against our local copy.
  ///
  /// [schoolId] must be the school that was just pulled (i.e.
  /// [effectiveSchoolId] from [_pullChanges]), NOT the member variable
  /// [schoolId], to avoid deleting teachers when an admin-override school
  /// was pulled.
  Future<void> _reconcileTeacherRoster(
    Set<String> activeServerIds, {
    required String schoolId,
  }) async {
    final localTeachers = await (db.select(db.teachers)
          ..where((t) => t.schoolServerId.equals(schoolId)))
        .get();

    for (final teacher in localTeachers) {
      if (teacher.forcePasswordReset) continue;
      if (teacher.serverId != null &&
          !activeServerIds.contains(teacher.serverId)) {
        try {
          await (db.update(db.teachers)
                ..where((t) => t.localId.equals(teacher.localId)))
              .write(const TeachersCompanion(
            isDeleted: Value(true),
          ));
          debugPrint(
            '[sync] _reconcileTeacherRoster: SOFT-DELETED teacher '
            '${teacher.serverId} (not in server roster)',
          );
        } catch (e, st) {
          debugPrint(
            '[sync] _reconcileTeacherRoster: failed to soft-delete teacher '
            '${teacher.serverId}: $e',
          );
          await Sentry.captureException(
            e,
            stackTrace: st,
          );
        }
      }
    }
  }

  /// Normalizes a subject name the same way the sync-push edge function does:
  /// trim, collapse internal whitespace, lowercase. Used so local names like
  /// "english  studies" match server rows like "English Studies".
  String _normalizeSubjectName(String name) {
    return name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  /// Permanent, automatic subject-sync self-heal.
  ///
  /// Reconciles the local [subjects] table against the full server subject
  /// catalog for the current school (fetched by sync-pull independently of
  /// the incremental cursor):
  ///
  ///  * Subject entirely absent server-side -> clear a stale/wrong local
  ///    `server_id` and queue a clean subjects INSERT (unless one is already
  ///    pending). Repairs rows that were dropped from the sync queue by the
  ///    old cross-table local_id collision (wrong server_id stored locally,
  ///    entry silently removed as "updated" against a non-subject UUID).
  ///  * Active matching subject exists server-side -> adopt the correct
  ///    server id and drop any pending INSERT so a subject the server already
  ///    has is never re-pushed.
  ///  * Only a soft-deleted/inactive matching subject exists -> leave the
  ///    local row unchanged and log a warning (never re-create a deliberately
  ///    removed subject).
  ///
  /// Idempotent: after healing, the next catalog contains the subject, so a
  /// later cycle matches by name and makes no further changes. School-scoped
  /// via [effectiveSchoolId]; teacher-safe (only touches the local subjects
  /// table and the local sync queue).
  Future<void> _reconcileLocalSubjects(
    List<Map<String, dynamic>> serverSubjects, {
    required String effectiveSchoolId,
  }) async {
    // Active server rows (ignoring soft-deleted / inactive) grouped by
    // normalized name. The catalog is already school-scoped server-side.
    final activeByName = <String, List<Map<String, dynamic>>>{};
    // Normalized names that exist on the server only as soft-deleted or
    // inactive rows — these must NOT be re-pushed.
    final inactiveOnlyNames = <String>{};

    for (final row in serverSubjects) {
      final rawName = (row['subject_name'] as String? ?? '').trim();
      if (rawName.isEmpty) continue;
      final normalized = _normalizeSubjectName(rawName);
      final deletedAt = row['deleted_at'];
      final isDeleted = deletedAt != null && deletedAt.toString().isNotEmpty;
      final isActive = row['is_active'] == null ||
          row['is_active'] == true ||
          row['is_active'] == 'true';
      if (isDeleted || !isActive) {
        inactiveOnlyNames.add(normalized);
      } else {
        activeByName.putIfAbsent(normalized, () => []).add(row);
      }
    }

    // Pending queue state so we never queue a duplicate INSERT.
    final pending = await store.loadPendingQueue();
    final pendingSubjectsForLocalId = <int>{};
    final pendingSubjectNames = <String>{};
    for (final entry in pending) {
      if (entry.queueTable != 'subjects') continue;
      pendingSubjectsForLocalId.add(entry.recordLocalId);
      if (entry.operation == 'INSERT') {
        final name = _decodePayload(entry.payload)['name'] as String?;
        if (name != null && name.isNotEmpty) {
          pendingSubjectNames.add(_normalizeSubjectName(name));
        }
      }
    }

    // Local subjects belonging to the current school. STRICT school scoping
    // (Fix 4): a null schoolId is never treated as "this school" when more
    // than one school could exist locally — unscoped rows are simply not
    // reconciled (surfaced by the caller as `unscoped`).
    final localSubjects = await (db.select(db.subjects)
          ..where((t) => t.schoolId.equals(effectiveSchoolId)))
        .get();

    var repaired = 0;
    // One INSERT per normalized name, even if duplicate local rows exist.
    final queuedNames = <String>{};
    // Local subject names whose server-side dependency was just healed or
    // adopted — dependent queue entries (scheme_of_work / lessons / exams)
    // referencing them carry stale retry cooldowns that must be cleared
    // after the loop (see _resetCooldownsForSubjectDependents).
    final healedNames = <String>{};

    for (final local in localSubjects) {
      final name = local.name.trim();
      if (name.isEmpty) continue;
      final normalized = _normalizeSubjectName(name);

      final activeMatches = activeByName[normalized] ?? const [];

      // ── Case: an active server subject with this name exists ─────────
      if (activeMatches.isNotEmpty) {
        final serverRow = activeMatches.first;
        final serverId = serverRow['id'] as String?;
        if (serverId != null &&
            serverId.isNotEmpty &&
            (local.serverId == null || local.serverId != serverId)) {
          await (db.update(db.subjects)
                ..where((t) => t.id.equals(local.id)))
              .write(SubjectsCompanion(
            serverId: Value(serverId),
            updatedAt: Value(DateTime.now()),
          ));
          debugPrint(
            '[SYNC-SUBJECT-HEAL] Adopted server_id $serverId for subject '
            '"${local.name}" (localId=${local.id})',
          );
          // The subject now resolves server-side — dependents that were
          // failing because it didn't are unblocked; clear their cooldowns.
          healedNames.add(name);
        }
        // Never re-push a subject the server already has.
        for (final entry in pending) {
          if (entry.queueTable == 'subjects' &&
              entry.recordLocalId == local.id) {
            await store.removeQueueEntry(entry.id);
          }
        }
        continue;
      }

      // ── Case: name exists only as soft-deleted / inactive ────────────
      // Never re-create a deliberately removed subject; warn and leave the
      // local row untouched.
      if (inactiveOnlyNames.contains(normalized)) {
        debugPrint(
          '[SYNC-SUBJECT-HEAL] Subject "${local.name}" exists on the server '
          'but is soft-deleted/inactive — leaving local row unchanged '
          '(localId=${local.id})',
        );
        continue;
      }

      // ── Case: subject entirely absent server-side -> repair ──────────
      // Whether the INSERT is queued below or already pending, the subject
      // is missing and queued for INSERT — dependents' cooldowns are stale.
      healedNames.add(name);
      if (local.serverId != null) {
        await (db.update(db.subjects)
              ..where((t) => t.id.equals(local.id)))
            .write(SubjectsCompanion(
          serverId: const Value(null),
          updatedAt: Value(DateTime.now()),
        ));
        debugPrint(
          '[SYNC-SUBJECT-HEAL] Cleared stale server_id for subject '
          '"${local.name}" (localId=${local.id})',
        );
      }
      if (pendingSubjectsForLocalId.contains(local.id)) {
        continue; // an INSERT for this row is already pending
      }
      if (pendingSubjectNames.contains(normalized)) {
        continue; // an INSERT with this name is already pending
      }
      if (!queuedNames.add(normalized)) {
        continue; // another local row with this name is being re-pushed
      }
      await db.syncQueueDao.insertEntry(
        queueTable: 'subjects',
        recordLocalId: local.id,
        operation: 'INSERT',
        payload: {'name': local.name, 'school_id': effectiveSchoolId},
      );
      repaired++;
    }

    if (repaired > 0) {
      debugPrint('[SYNC-SUBJECT-HEAL] Repaired $repaired subject(s)');
    }

    // After healing/adopting, clear the retry cooldown on dependent queue
    // entries referencing each subject so they become due for push instead
    // of being skipped by the cooldown filter for up to an hour.
    for (final healedName in healedNames) {
      await _resetCooldownsForSubjectDependents(healedName);
    }
  }

  /// Clears the retry cooldown on pending sync_queue entries whose payload
  /// references [subjectName] — scheme_of_work (payload['subject_name']) and
  /// lessons / exams (payload['subject']) — immediately after the subject was
  /// healed or adopted by [_reconcileLocalSubjects].
  ///
  /// Entries that failed only because the subject did not exist server-side
  /// carry a stale next_retry_at that keeps them out of the push batch even
  /// though the dependency is now repaired. Resetting their retry state
  /// (next_retry_at = NULL, attempts = 0, last_attempt_at = NULL) makes them
  /// due for push on the next cycle; is_terminal is never touched so they
  /// stay pending.
  ///
  /// Idempotent: entries already out of cooldown are simply reset again.
  Future<void> _resetCooldownsForSubjectDependents(String subjectName) async {
    final needle = _normalizeSubjectName(subjectName);
    if (needle.isEmpty) return;

    final pending = await store.loadPendingQueue();
    var resetCount = 0;
    for (final entry in pending) {
      final table = entry.queueTable;
      if (table != 'scheme_of_work' &&
          table != 'lessons' &&
          table != 'exams') {
        continue;
      }
      final payload = _decodePayload(entry.payload);
      final rawSubject = table == 'scheme_of_work'
          ? payload['subject_name']
          : payload['subject'];
      if (rawSubject == null) continue;
      final raw = rawSubject.toString().trim();
      if (raw.isEmpty || _normalizeSubjectName(raw) != needle) continue;

      await db.syncQueueDao.resetRetryState(entry.id);
      resetCount++;
    }

    if (resetCount > 0) {
      debugPrint('[SYNC-HEAL] Reset cooldown for $resetCount dependent '
          'entries for subject "$subjectName"');
    }
  }

  /// Broad, permanent cooldown reset for dependent queue entries
  /// (scheme_of_work / lessons / exams) referencing subjects that already
  /// exist server-side.
  ///
  /// The per-cycle heal/adopt path in [_reconcileLocalSubjects] only clears
  /// cooldowns for subjects it actually healed or adopted in the CURRENT
  /// cycle. Once a subject carries a correct server_id (the steady state),
  /// that branch never runs — so dependent entries that re-entered cooldown
  /// after a transient failure stay stuck (next_retry_at in the future) even
  /// though their subject dependency is fully resolved. This method closes
  /// that gap on every successful pull.
  ///
  /// Loads the current school's local subjects that already have a non-empty
  /// server_id, then for each pending dependent entry whose payload subject
  /// name matches (via [_normalizeSubjectName]; scheme_of_work uses
  /// payload['subject_name'], lessons/exams use payload['subject']) resets
  /// its retry state (next_retry_at = NULL, attempts = 0, last_attempt_at =
  /// NULL) so it becomes due for push on the next cycle. is_terminal is
  /// never touched — pending entries stay pending.
  ///
  /// Idempotent: entries already out of cooldown are reset again harmlessly;
  /// a dependent that fails again for a different reason simply re-enters
  /// cooldown (the normal retry backoff still governs the actual push
  /// attempt), and the next pull resets it only if its subject still exists
  /// server-side.
  Future<void> _resetCooldownsForExistingServerSubjects() async {
    // (a) Current school's local subjects that already exist server-side
    // (non-empty server_id).
    final localSubjects = await (db.select(db.subjects)
          ..where((t) => t.schoolId.equals(schoolId)))
        .get();
    final serverSubjectNames = <String>{};
    for (final subject in localSubjects) {
      final sid = subject.serverId;
      if (sid == null || sid.isEmpty) continue;
      final normalized = _normalizeSubjectName(subject.name);
      if (normalized.isNotEmpty) serverSubjectNames.add(normalized);
    }
    if (serverSubjectNames.isEmpty) return;

    // (b) All pending queue entries.
    final pending = await store.loadPendingQueue();
    var resetCount = 0;

    for (final entry in pending) {
      final table = entry.queueTable;
      if (table != 'scheme_of_work' &&
          table != 'lessons' &&
          table != 'exams') {
        continue;
      }
      // (d) Only entries currently in cooldown need a reset.
      if (entry.nextRetryAt == null) continue;

      // (c) Decode the payload and match by subject name.
      final payload = _decodePayload(entry.payload);
      final rawSubject = table == 'scheme_of_work'
          ? payload['subject_name']
          : payload['subject'];
      if (rawSubject == null) continue;
      final raw = rawSubject.toString().trim();
      if (raw.isEmpty ||
          !serverSubjectNames.contains(_normalizeSubjectName(raw))) {
        continue;
      }

      await db.syncQueueDao.resetRetryState(entry.id);
      resetCount++;
    }

    // (e) Summary line; (f) is_terminal is never touched by resetRetryState.
    if (resetCount > 0) {
      debugPrint('[SYNC-HEAL] Reset cooldown for $resetCount dependent '
          'entries for existing server subjects');
    }
  }

  // ═══════════════════════════════════════════════════════════════════════
  // Full-table reconciliation (generalizes the subject self-heal to lessons,
  // exams, scheme_of_work, and progress_logs). See
  // plans/sync_full_table_reconciliation.md — Fixes 1-4, 6-7.
  // ═══════════════════════════════════════════════════════════════════════

  /// Stop-limit (Fix 6): a missing row is re-queued at most this many times
  /// before it is flagged for manual review. progress_logs uses 1 (one-shot,
  /// Fix 1) so an append-only event is never auto-requeued twice.
  static const int _reconcileMaxAttemptsLessonsExamsSow = 3;
  static const int _reconcileMaxAttemptsProgressLogs = 1;

  /// Last-cycle per-table counters (repaired/adopted/inactive/unscoped/
  /// flagged) so [debugDumpReconcileIssues] can surface unscoped/ambiguous
  /// counts without a UI (Fix 7).
  final Map<String, Map<String, int>> _lastReconcileCounts = {};

  String _normKey(String value) =>
      value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  int? _toUtcMs(dynamic value) {
    if (value == null) return null;
    final parsed = value is DateTime ? value : DateTime.tryParse(value.toString());
    return parsed?.toUtc().millisecondsSinceEpoch;
  }

  /// A catalog row counts as inactive when it is soft-deleted (`is_deleted`)
  /// or has a non-empty `deleted_at`.
  bool _isInactiveCatalogRow(Map<String, dynamic> row) {
    final deletedAt = row['deleted_at'];
    final hasDeletedAt = deletedAt != null && deletedAt.toString().isNotEmpty;
    final raw = row['is_deleted'];
    final softDeleted = raw == true || raw == 'true' || raw == 1;
    return softDeleted || hasDeletedAt;
  }

  /// Dispatcher: loads the local FK resolution maps once, then reconciles
  /// each table whose catalog was returned. Skipped entirely when the pull
  /// failed (catalog map null) or no active school is known.
  Future<void> _reconcileMissingLocalRows(
    Map<String, List<Map<String, dynamic>>> catalogs, {
    required String effectiveSchoolId,
  }) async {
    final teachers = await (db.select(db.teachers)).get();
    final subjects = await (db.select(db.subjects)).get();
    final teacherServerIdByLocalId = <int, String>{};
    final subjectServerIdByLocalId = <int, String>{};
    final subjectServerIdByNormName = <String, String>{};
    for (final t in teachers) {
      final sid = t.serverId;
      if (sid != null && sid.isNotEmpty) {
        teacherServerIdByLocalId[t.localId] = sid;
      }
    }
    for (final s in subjects) {
      final sid = s.serverId;
      if (sid != null && sid.isNotEmpty) {
        subjectServerIdByLocalId[s.id] = sid;
        subjectServerIdByNormName.putIfAbsent(_normKey(s.name), () => sid);
      }
    }

    final lessons = catalogs['lessons'];
    if (lessons != null) {
      await _reconcileLocalLessons(
        lessons,
        effectiveSchoolId: effectiveSchoolId,
        subjectServerIdByNormName: subjectServerIdByNormName,
      );
    }
    final exams = catalogs['exams'];
    if (exams != null) {
      await _reconcileLocalExams(
        exams,
        effectiveSchoolId: effectiveSchoolId,
        subjectServerIdByNormName: subjectServerIdByNormName,
      );
    }
    final sow = catalogs['scheme_of_work'];
    if (sow != null) {
      await _reconcileLocalSchemeOfWork(
        sow,
        effectiveSchoolId: effectiveSchoolId,
        teacherServerIdByLocalId: teacherServerIdByLocalId,
        subjectServerIdByLocalId: subjectServerIdByLocalId,
      );
    }
    final progress = catalogs['progress_logs'];
    if (progress != null) {
      await _reconcileLocalProgressLogs(
        progress,
        effectiveSchoolId: effectiveSchoolId,
        teacherServerIdByLocalId: teacherServerIdByLocalId,
      );
    }
  }

  /// Removes pending INSERT queue entries for (table, localId) — used when a
  /// row matched the server at Tier 1/2 so a stale INSERT can never re-create
  /// a row the server already has.
  Future<void> _dropPendingInserts(
    List<SyncQueueData> pending,
    String table,
    int localId,
  ) async {
    for (final entry in pending) {
      if (entry.queueTable == table &&
          entry.recordLocalId == localId &&
          entry.operation == 'INSERT') {
        await store.removeQueueEntry(entry.id);
      }
    }
  }

  /// Deletes any TERMINAL INSERT entry for (table, localId) so a freshly
  /// re-queued clean INSERT never sits next to a dead twin.
  Future<void> _deleteTerminalInsertTwin(String table, int localId) async {
    final twins = await (db.select(db.syncQueue)
          ..where((t) =>
              t.isTerminal.equals(true) &
              t.queueTable.equals(table) &
              t.recordLocalId.equals(localId) &
              t.operation.equals('INSERT')))
        .get();
    for (final twin in twins) {
      await db.syncQueueDao.deleteById(twin.id);
    }
  }

  /// The generalized per-table reconciliation core. Implements the tiered
  /// matching of C.2 exactly: strict school scope (applied by the caller via
  /// [scopedRows]/[unscopedCount]), Tier 1 (server_id), Tier 2 (natural key,
  /// Fix 3 safe rule), inactive-only warn, then missing → repair with the
  /// stop-limit (Fix 6) / one-shot (Fix 1). Logs one summary line per table.
  Future<void> _reconcileTableRows<T>({
    required String table,
    required List<Map<String, dynamic>> catalog,
    required int maxAttempts,
    required int unscopedCount,
    required List<T> scopedRows,
    required int Function(T row) localIdOf,
    required String? Function(T row) serverIdOf,
    required String? Function(Map<String, dynamic> catalogRow)
        naturalKeyFromCatalog,
    required String? Function(T row) naturalKeyOf,
    required Future<void> Function(T row, String serverId) adoptServerId,
    required Future<void> Function(T row) clearServerId,
    required Future<Map<String, dynamic>?> Function(T row) buildPayload,
    required String Function(T row) logLabel,
  }) async {
    final activeById = <String, Map<String, dynamic>>{};
    final inactiveById = <String, Map<String, dynamic>>{};
    final activeByKey = <String, List<Map<String, dynamic>>>{};
    final inactiveKeys = <String>{};
    for (final row in catalog) {
      final id = row['id'] as String?;
      if (id == null || id.isEmpty) continue;
      final key = naturalKeyFromCatalog(row);
      if (_isInactiveCatalogRow(row)) {
        inactiveById[id] = row;
        if (key != null) inactiveKeys.add(key);
        continue;
      }
      activeById[id] = row;
      if (key != null) {
        activeByKey.putIfAbsent(key, () => []).add(row);
      }
    }

    final pending = await store.loadPendingQueue();
    final pendingInserts = <int>{};
    for (final entry in pending) {
      if (entry.queueTable == table && entry.operation == 'INSERT') {
        pendingInserts.add(entry.recordLocalId);
      }
    }

    var repaired = 0, adopted = 0, inactiveWarned = 0, flagged = 0;

    for (final local in scopedRows) {
      final localId = localIdOf(local);
      final label = logLabel(local);
      final serverId = serverIdOf(local);
      final key = naturalKeyOf(local);

      // ── Tier 1 — server_id match ──────────────────────────────────────
      if (serverId != null && serverId.isNotEmpty) {
        if (activeById.containsKey(serverId)) {
          await _dropPendingInserts(pending, table, localId);
          await db.syncReconcileStateDao.clearFor(table, localId);
          continue;
        }
        // The existing id references a REAL row of this table (inactive) —
        // never rebind it, even if the natural key diverges (Fix 3 case 2).
        if (inactiveById.containsKey(serverId)) {
          inactiveWarned++;
          debugPrint('[SYNC-HEAL] $label: server row $serverId exists but is '
              'soft-deleted/inactive — leaving local row unchanged');
          continue;
        }
      }

      // ── Tier 2 — natural-key match (Fix 3 safe rule) ──────────────────
      final matches = key != null
          ? (activeByKey[key] ?? const <Map<String, dynamic>>[])
          : const <Map<String, dynamic>>[];
      if (matches.isNotEmpty) {
        if (matches.length > 1) {
          // Ambiguous natural key (Fix 2 defensive rule): adopt nothing,
          // re-queue nothing.
          flagged++;
          debugPrint('[SYNC-HEAL] $label: natural key matches '
              '${matches.length} active server rows — ambiguous, needs '
              'manual review');
          continue;
        }
        final matchId = matches.first['id'] as String?;
        if (matchId == null || matchId.isEmpty) continue;
        if (serverId != null && serverId.isNotEmpty) {
          // serverId is provably absent from the entire catalog — not a row
          // of this table in this school (e.g. the old cross-table collision
          // id). Adopt with an explicit reason (Fix 3 case 3).
          debugPrint('[SYNC-HEAL] $label: server_id $serverId is not a row of '
              'table $table in this school\'s catalog — adopting $matchId '
              'via natural key');
        }
        await adoptServerId(local, matchId);
        await _dropPendingInserts(pending, table, localId);
        await db.syncReconcileStateDao.clearFor(table, localId);
        adopted++;
        continue;
      }

      // ── Only inactive server rows exist for this key — never re-create ─
      if (key != null && inactiveKeys.contains(key)) {
        inactiveWarned++;
        debugPrint('[SYNC-HEAL] $label: soft-deleted/inactive on server — '
            'leaving local row unchanged');
        continue;
      }

      // ── Missing → repair (stop-limit / one-shot first) ────────────────
      final attempts =
          (await db.syncReconcileStateDao.getFor(table, localId))?.attempts ??
              0;
      if (attempts >= maxAttempts) {
        flagged++;
        debugPrint('[SYNC-HEAL] $label: no server match after $attempts '
            'cycle(s) — needs manual review, not re-queued');
        continue;
      }
      if (serverId != null && serverId.isNotEmpty) {
        await clearServerId(local);
        debugPrint('[SYNC-HEAL] $label: cleared stale server_id $serverId');
      }
      if (pendingInserts.contains(localId)) {
        continue; // an INSERT for this row is already pending
      }
      await _deleteTerminalInsertTwin(table, localId);
      final payload = await buildPayload(local);
      if (payload == null) {
        flagged++; // reason already logged by the builder
        continue;
      }
      await db.syncQueueDao.insertEntry(
        queueTable: table,
        recordLocalId: localId,
        operation: 'INSERT',
        payload: payload,
      );
      await db.syncReconcileStateDao.recordAttempt(table, localId);
      repaired++;
    }

    _lastReconcileCounts[table] = {
      'repaired': repaired,
      'adopted': adopted,
      'inactive': inactiveWarned,
      'unscoped': unscopedCount,
      'flagged': flagged,
    };
    debugPrint('[SYNC-HEAL] $table: $repaired repaired, $adopted adopted, '
        '$inactiveWarned inactive, $unscopedCount unscoped, '
        '$flagged flagged');
  }

  // ── Natural-key builders ────────────────────────────────────────────────

  String? _lessonKeyFromCatalog(Map<String, dynamic> row) {
    final teacherId = row['teacher_id'] as String?;
    final subjectId = row['subject_id'] as String?;
    if (teacherId == null || teacherId.isEmpty) return null;
    if (subjectId == null || subjectId.isEmpty) return null;
    final week = _toInt(row['week']) ?? 0;
    return 'l|${_normKey(row['school_id'] as String? ?? '')}|'
        '${_normKey(teacherId)}|${_normKey(subjectId)}|'
        '${_normKey(row['class_level'] as String? ?? '')}|$week|'
        '${_normKey(row['term'] as String? ?? '')}';
  }

  String? _lessonKeyFromLocal(
    Lesson r,
    Map<String, String> subjectServerIdByNormName,
  ) {
    final teacherId = r.teacherServerId;
    final subjectId = subjectServerIdByNormName[_normKey(r.subject)];
    if (teacherId == null || teacherId.isEmpty) return null;
    if (subjectId == null || subjectId.isEmpty) return null;
    return 'l|${_normKey(r.schoolServerId ?? '')}|${_normKey(teacherId)}|'
        '${_normKey(subjectId)}|${_normKey(r.classLevel)}|${r.week}|'
        '${_normKey(r.term ?? '')}';
  }

  String? _examKeyFromCatalog(Map<String, dynamic> row) {
    final teacherId = row['teacher_id'] as String?;
    final subjectId = row['subject_id'] as String?;
    if (teacherId == null || teacherId.isEmpty) return null;
    if (subjectId == null || subjectId.isEmpty) return null;
    final weekNumber = _toInt(row['week_number']) ?? 0;
    return 'e|${_normKey(row['school_id'] as String? ?? '')}|'
        '${_normKey(teacherId)}|${_normKey(subjectId)}|'
        '${_normKey(row['class_level'] as String? ?? '')}|$weekNumber|'
        '${_normKey(row['term'] as String? ?? '')}|'
        '${_normKey(row['topic'] as String? ?? '')}';
  }

  String? _examKeyFromLocal(
    Exam r,
    Map<String, String> subjectServerIdByNormName,
  ) {
    final teacherId = r.teacherServerId;
    final subjectId = subjectServerIdByNormName[_normKey(r.subject)];
    if (teacherId == null || teacherId.isEmpty) return null;
    if (subjectId == null || subjectId.isEmpty) return null;
    return 'e|${_normKey(r.schoolServerId ?? '')}|${_normKey(teacherId)}|'
        '${_normKey(subjectId)}|${_normKey(r.classLevel)}|${r.weekNumber ?? 0}|'
        '${_normKey(r.term ?? '')}|${_normKey(r.topic)}';
  }

  String? _sowKeyFromCatalog(Map<String, dynamic> row) {
    final subjectId = row['subject_id'] as String?;
    if (subjectId == null || subjectId.isEmpty) return null;
    final weekNumber = _toInt(row['week_number']) ?? 0;
    return 's|${_normKey(row['school_id'] as String? ?? '')}|'
        '${_normKey(subjectId)}|${_normKey(row['term'] as String? ?? '')}|'
        '$weekNumber';
  }

  String? _sowKeyFromLocal(
    SchemeOfWorkData r,
    Map<int, String> subjectServerIdByLocalId,
    String effectiveSchoolId,
  ) {
    final subjectId = subjectServerIdByLocalId[r.subjectId];
    if (subjectId == null || subjectId.isEmpty) return null;
    return 's|${_normKey(effectiveSchoolId)}|${_normKey(subjectId)}|'
        '${_normKey(r.term)}|${r.weekNumber}';
  }

  String? _progressKeyFromCatalog(Map<String, dynamic> row) {
    final teacherId = row['teacher_id'] as String?;
    if (teacherId == null || teacherId.isEmpty) return null;
    final eventDateMs = _toUtcMs(row['event_date']);
    if (eventDateMs == null) return null;
    return 'p|${_normKey(row['school_id'] as String? ?? '')}|'
        '${_normKey(teacherId)}|'
        '${_normKey(row['event_type'] as String? ?? '')}|$eventDateMs';
  }

  String? _progressKeyFromLocal(
    ProgressLog r,
    Map<int, String> teacherServerIdByLocalId,
    String effectiveSchoolId,
  ) {
    final teacherId = teacherServerIdByLocalId[r.teacherId];
    if (teacherId == null || teacherId.isEmpty) return null;
    return 'p|${_normKey(effectiveSchoolId)}|${_normKey(teacherId)}|'
        '${_normKey(r.eventType)}|'
        '${r.eventDate.toUtc().millisecondsSinceEpoch}';
  }

  // ── Per-table wrappers (school scope + payloads) ────────────────────────

  Future<void> _reconcileLocalLessons(
    List<Map<String, dynamic>> catalog, {
    required String effectiveSchoolId,
    required Map<String, String> subjectServerIdByNormName,
  }) async {
    final localRows = await (db.select(db.lessons)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    var unscoped = 0;
    final scoped = <Lesson>[];
    for (final row in localRows) {
      if (row.schoolServerId == effectiveSchoolId) {
        scoped.add(row);
      } else {
        unscoped++;
      }
    }
    await _reconcileTableRows(
      table: 'lessons',
      catalog: catalog,
      maxAttempts: _reconcileMaxAttemptsLessonsExamsSow,
      unscopedCount: unscoped,
      scopedRows: scoped,
      localIdOf: (r) => r.id,
      serverIdOf: (r) => r.serverId,
      naturalKeyFromCatalog: _lessonKeyFromCatalog,
      naturalKeyOf: (r) =>
          _lessonKeyFromLocal(r, subjectServerIdByNormName),
      adoptServerId: (r, sid) async => (db.update(db.lessons)
            ..where((t) => t.id.equals(r.id)))
          .write(LessonsCompanion(
        serverId: Value(sid),
        updatedAt: Value(DateTime.now()),
      )),
      clearServerId: (r) async => (db.update(db.lessons)
            ..where((t) => t.id.equals(r.id)))
          .write(LessonsCompanion(
        serverId: const Value(null),
        updatedAt: Value(DateTime.now()),
      )),
      buildPayload: (r) async => _buildLessonInsertPayload(r),
      logLabel: (r) => 'lessons#${r.id} (${r.subject}/${r.topic})',
    );
  }

  Future<void> _reconcileLocalExams(
    List<Map<String, dynamic>> catalog, {
    required String effectiveSchoolId,
    required Map<String, String> subjectServerIdByNormName,
  }) async {
    final localRows = await (db.select(db.exams)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    var unscoped = 0;
    final scoped = <Exam>[];
    for (final row in localRows) {
      if (row.schoolServerId == effectiveSchoolId) {
        scoped.add(row);
      } else {
        unscoped++;
      }
    }
    await _reconcileTableRows(
      table: 'exams',
      catalog: catalog,
      maxAttempts: _reconcileMaxAttemptsLessonsExamsSow,
      unscopedCount: unscoped,
      scopedRows: scoped,
      localIdOf: (r) => r.id,
      serverIdOf: (r) => r.serverId,
      naturalKeyFromCatalog: _examKeyFromCatalog,
      naturalKeyOf: (r) => _examKeyFromLocal(r, subjectServerIdByNormName),
      adoptServerId: (r, sid) async => (db.update(db.exams)
            ..where((t) => t.id.equals(r.id)))
          .write(ExamsCompanion(
        serverId: Value(sid),
        updatedAt: Value(DateTime.now()),
      )),
      clearServerId: (r) async => (db.update(db.exams)
            ..where((t) => t.id.equals(r.id)))
          .write(ExamsCompanion(
        serverId: const Value(null),
        updatedAt: Value(DateTime.now()),
      )),
      buildPayload: (r) async => _buildExamInsertPayload(r),
      logLabel: (r) => 'exams#${r.id} (${r.subject}/${r.topic})',
    );
  }

  Future<void> _reconcileLocalSchemeOfWork(
    List<Map<String, dynamic>> catalog, {
    required String effectiveSchoolId,
    required Map<int, String> teacherServerIdByLocalId,
    required Map<int, String> subjectServerIdByLocalId,
  }) async {
    final school = await db.schoolsDao.getByServerId(effectiveSchoolId);
    final localRows = await (db.select(db.schemeOfWork)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    var unscoped = 0;
    final scoped = <SchemeOfWorkData>[];
    for (final row in localRows) {
      if (school != null && row.schoolId == school.localId) {
        scoped.add(row);
      } else {
        unscoped++;
      }
    }
    await _reconcileTableRows(
      table: 'scheme_of_work',
      catalog: catalog,
      maxAttempts: _reconcileMaxAttemptsLessonsExamsSow,
      unscopedCount: unscoped,
      scopedRows: scoped,
      localIdOf: (r) => r.id,
      serverIdOf: (r) => r.serverId,
      naturalKeyFromCatalog: _sowKeyFromCatalog,
      naturalKeyOf: (r) =>
          _sowKeyFromLocal(r, subjectServerIdByLocalId, effectiveSchoolId),
      adoptServerId: (r, sid) async => (db.update(db.schemeOfWork)
            ..where((t) => t.id.equals(r.id)))
          .write(SchemeOfWorkCompanion(
        serverId: Value(sid),
        updatedAt: Value(DateTime.now()),
      )),
      clearServerId: (r) async => (db.update(db.schemeOfWork)
            ..where((t) => t.id.equals(r.id)))
          .write(SchemeOfWorkCompanion(
        serverId: const Value(null),
        updatedAt: Value(DateTime.now()),
      )),
      buildPayload: (r) => _buildSchemeOfWorkInsertPayload(
        r,
        effectiveSchoolId: effectiveSchoolId,
        teacherServerIdByLocalId: teacherServerIdByLocalId,
        subjectServerIdByLocalId: subjectServerIdByLocalId,
      ),
      logLabel: (r) =>
          'scheme_of_work#${r.id} (term=${r.term} week=${r.weekNumber})',
    );
  }

  Future<void> _reconcileLocalProgressLogs(
    List<Map<String, dynamic>> catalog, {
    required String effectiveSchoolId,
    required Map<int, String> teacherServerIdByLocalId,
  }) async {
    final school = await db.schoolsDao.getByServerId(effectiveSchoolId);
    final localRows = await (db.select(db.progressLogs)
          ..where((t) => t.isDeleted.equals(false)))
        .get();
    var unscoped = 0;
    final scoped = <ProgressLog>[];
    for (final row in localRows) {
      if (school != null && row.schoolId == school.localId) {
        scoped.add(row);
      } else {
        unscoped++;
      }
    }
    await _reconcileTableRows(
      table: 'progress_logs',
      catalog: catalog,
      maxAttempts: _reconcileMaxAttemptsProgressLogs,
      unscopedCount: unscoped,
      scopedRows: scoped,
      localIdOf: (r) => r.id,
      serverIdOf: (r) => r.serverId,
      naturalKeyFromCatalog: _progressKeyFromCatalog,
      naturalKeyOf: (r) =>
          _progressKeyFromLocal(r, teacherServerIdByLocalId, effectiveSchoolId),
      adoptServerId: (r, sid) async => (db.update(db.progressLogs)
            ..where((t) => t.id.equals(r.id)))
          .write(ProgressLogsCompanion(
        serverId: Value(sid),
        updatedAt: Value(DateTime.now()),
      )),
      clearServerId: (r) async => (db.update(db.progressLogs)
            ..where((t) => t.id.equals(r.id)))
          .write(ProgressLogsCompanion(
        serverId: const Value(null),
        updatedAt: Value(DateTime.now()),
      )),
      buildPayload: (r) => _buildProgressLogInsertPayload(
        r,
        effectiveSchoolId: effectiveSchoolId,
        teacherServerIdByLocalId: teacherServerIdByLocalId,
      ),
      logLabel: (r) =>
          'progress_logs#${r.id} (${r.eventType} @ ${r.eventDate.toIso8601String()})',
    );
  }

  // ── Payload builders (byte-identical to the current queue sites) ────────

  Map<String, dynamic>? _buildLessonInsertPayload(Lesson r) {
    final teacherServerId = r.teacherServerId;
    if (teacherServerId == null || teacherServerId.isEmpty) {
      debugPrint('[SYNC-HEAL] lessons#${r.id}: cannot resolve teacher server '
          'id — skipping re-push');
      return null;
    }
    return {
      'subject': r.subject,
      'classLevel': r.classLevel,
      'week': r.week,
      'topic': r.topic,
      'difficulty': r.difficulty,
      'bloomsVerbs': r.bloomsVerbs,
      'curriculum': r.curriculum,
      'teacher_server_id': teacherServerId,
      'school_server_id': r.schoolServerId,
      'content': r.content,
      'content_hash': r.contentHash ?? r.content.hashCode.toString(),
      'is_unlocked': r.isUnlocked,
      'status': r.status,
      if (r.schemeOfWorkId != null && r.schemeOfWorkId!.isNotEmpty)
        'scheme_of_work_id': r.schemeOfWorkId,
      'week_number': r.weekNumber ?? r.week,
      if (r.term != null && r.term!.isNotEmpty) 'term': r.term,
    };
  }

  Map<String, dynamic>? _buildExamInsertPayload(Exam r) {
    final teacherServerId = r.teacherServerId;
    if (teacherServerId == null || teacherServerId.isEmpty) {
      debugPrint('[SYNC-HEAL] exams#${r.id}: cannot resolve teacher server '
          'id — skipping re-push');
      return null;
    }
    return {
      'subject': r.subject,
      'classLevel': r.classLevel,
      'topic': r.topic,
      'difficulty': r.difficulty,
      'curriculum': r.curriculum,
      'teacher_server_id': teacherServerId,
      'school_server_id': r.schoolServerId,
      'content': r.content,
      'is_unlocked': r.isUnlocked,
      if (r.schemeOfWorkId != null && r.schemeOfWorkId!.isNotEmpty)
        'scheme_of_work_id': r.schemeOfWorkId,
      'week_number': r.weekNumber ?? 0,
      if (r.term != null && r.term!.isNotEmpty) 'term': r.term,
    };
  }

  Future<Map<String, dynamic>?> _buildSchemeOfWorkInsertPayload(
    SchemeOfWorkData r, {
    required String effectiveSchoolId,
    required Map<int, String> teacherServerIdByLocalId,
    required Map<int, String> subjectServerIdByLocalId,
  }) async {
    final teacherServerId = teacherServerIdByLocalId[r.teacherId];
    if (teacherServerId == null || teacherServerId.isEmpty) {
      debugPrint('[SYNC-HEAL] scheme_of_work#${r.id}: cannot resolve teacher '
          'server id (local teacherId=${r.teacherId}) — skipping re-push');
      return null;
    }
    final subjectServerId = subjectServerIdByLocalId[r.subjectId];
    final subject = await db.subjectsDao.getById(r.subjectId);
    if (subjectServerId == null &&
        (subject == null || subject.name.trim().isEmpty)) {
      debugPrint('[SYNC-HEAL] scheme_of_work#${r.id}: no subject id or name '
          'resolvable — skipping re-push');
      return null;
    }
    return {
      'teacher_server_id': teacherServerId,
      'school_server_id': effectiveSchoolId,
      'subject_id': subjectServerId,
      'subject_name': subject?.name,
      'term': normalizeSowTermForServer(r.term),
      'week_number': r.weekNumber,
      'topic': r.topic,
      'objectives': r.objectives,
      'status': r.status,
      'admin_edited_topic': r.adminEditedTopic,
      'admin_comment': r.adminComment,
      'class_level': r.classLevel,
    };
  }

  Future<Map<String, dynamic>?> _buildProgressLogInsertPayload(
    ProgressLog r, {
    required String effectiveSchoolId,
    required Map<int, String> teacherServerIdByLocalId,
  }) async {
    final teacherServerId = teacherServerIdByLocalId[r.teacherId];
    if (teacherServerId == null || teacherServerId.isEmpty) {
      debugPrint('[SYNC-HEAL] progress_logs#${r.id}: cannot resolve teacher '
          'server id (local teacherId=${r.teacherId}) — skipping re-push');
      return null;
    }
    return {
      'event_type': r.eventType,
      'event_date': r.eventDate.toUtc().toIso8601String(),
      'lesson_id': r.lessonId,
      'teacher_id': teacherServerId,
      'school_id': effectiveSchoolId,
    };
  }

  /// Builds a clean INSERT payload for an UPDATE queue entry whose local row
  /// never received a server_id, reusing the EXACT payload builders the
  /// full-table reconciliation uses for that table. The converted entry is
  /// pushable and idempotent with the sync-push check-before-insert guard
  /// (a re-push lands on the existing server row as "updated" instead of
  /// duplicating). Returns null when the local row is gone or a required FK
  /// cannot be resolved — the builder logs the reason and the caller leaves
  /// the entry unchanged.
  Future<Map<String, dynamic>?> _buildInsertPayloadForQueuedUpdate(
    SyncQueueData entry, {
    required String effectiveSchoolId,
  }) async {
    switch (entry.queueTable) {
      case 'lessons':
        final row = await (db.select(db.lessons)
              ..where((t) => t.id.equals(entry.recordLocalId)))
            .getSingleOrNull();
        if (row == null) return null;
        return _buildLessonInsertPayload(row);
      case 'exams':
        final row = await (db.select(db.exams)
              ..where((t) => t.id.equals(entry.recordLocalId)))
            .getSingleOrNull();
        if (row == null) return null;
        return _buildExamInsertPayload(row);
      case 'scheme_of_work':
        final row = await (db.select(db.schemeOfWork)
              ..where((t) => t.id.equals(entry.recordLocalId)))
            .getSingleOrNull();
        if (row == null) return null;
        final teacher = await (db.select(db.teachers)
              ..where((t) => t.localId.equals(row.teacherId)))
            .getSingleOrNull();
        final subject = await (db.select(db.subjects)
              ..where((t) => t.id.equals(row.subjectId)))
            .getSingleOrNull();
        return _buildSchemeOfWorkInsertPayload(
          row,
          effectiveSchoolId: effectiveSchoolId,
          teacherServerIdByLocalId: {
            if (teacher != null && teacher.serverId != null)
              row.teacherId: teacher.serverId!,
          },
          subjectServerIdByLocalId: {
            if (subject != null && subject.serverId != null)
              row.subjectId: subject.serverId!,
          },
        );
      case 'progress_logs':
        final row = await (db.select(db.progressLogs)
              ..where((t) => t.id.equals(entry.recordLocalId)))
            .getSingleOrNull();
        if (row == null) return null;
        final teacher = await (db.select(db.teachers)
              ..where((t) => t.localId.equals(row.teacherId)))
            .getSingleOrNull();
        return _buildProgressLogInsertPayload(
          row,
          effectiveSchoolId: effectiveSchoolId,
          teacherServerIdByLocalId: {
            if (teacher != null && teacher.serverId != null)
              row.teacherId: teacher.serverId!,
          },
        );
      default:
        return null;
    }
  }

  /// Fix 7: surfaces every tracked reconcile-state row (with its attempt
  /// count and whether it is over threshold) plus the last cycle's per-table
  /// unscoped/ambiguous counts, so flagged rows reach a person. Runs at the
  /// end of each successful pull (see [_pullChanges]) and is callable
  /// manually. No UI — the output lands in the app log stream filtered on
  /// `SYNC-HEAL`, and the lines are returned so tests can assert on them.
  Future<List<String>> debugDumpReconcileIssues() async {
    final lines = <String>[];
    final all = await db.syncReconcileStateDao.getAll();
    lines.add('[SYNC-HEAL] debugDumpReconcileIssues: ${all.length} tracked '
        'row(s)');
    for (final state in all) {
      final maxA = state.recordTable == 'progress_logs'
          ? _reconcileMaxAttemptsProgressLogs
          : _reconcileMaxAttemptsLessonsExamsSow;
      final over = state.attempts >= maxA;
      lines.add('[SYNC-HEAL]   ${state.recordTable} localId=${state.localId} '
          'attempts=${state.attempts}/$maxA '
          'lastAttemptedAt=${state.lastAttemptedAt}'
          '${over ? ' — OVER THRESHOLD, needs manual review' : ''}');
    }
    _lastReconcileCounts.forEach((table, counts) {
      lines.add('[SYNC-HEAL]   $table last-cycle counts: $counts');
    });
    for (final line in lines) {
      debugPrint(line);
    }
    return lines;
  }

  Future<MergeResult> _threeWayMerge(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
    String tableName,
    Map<String, dynamic>? base,
  ) async {
    return mergeEngine.merge(
      local: local,
      remote: remote,
      base: base,
      tableName: tableName,
      fieldStrategies: mergeStrategiesForTable(tableName),
    );
  }

  DateTime? _parseDateTimeValue(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  bool _valuesEqual(dynamic a, dynamic b) {
    if (identical(a, b)) return true;
    if (a == null || b == null) return false;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key)) return false;
        if (!_valuesEqual(entry.value, b[entry.key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_valuesEqual(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }

  bool _isTimestampTiebreakWin({
    required MapEntry<String, MergeStrategy> strategyEntry,
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required Map<String, dynamic> base,
  }) {
    if (strategyEntry.value != MergeStrategy.lwwByUpdateCounterThenUpdatedAt) {
      return false;
    }

    final fieldName = strategyEntry.key;
    final localValue = local[fieldName];
    final remoteValue = remote[fieldName];
    final baseValue = base[fieldName];

    if (_valuesEqual(localValue, baseValue) ||
        _valuesEqual(remoteValue, baseValue)) {
      return false;
    }
    if (_valuesEqual(localValue, remoteValue)) {
      return false;
    }

    final localUpdateCounter = (local['updateCounter'] as int?) ?? 0;
    final remoteUpdateCounter = (remote['updateCounter'] as int?) ?? 0;
    if (localUpdateCounter != remoteUpdateCounter) {
      return false;
    }

    final localUpdatedAt = _parseDateTimeValue(local['updatedAt']);
    final remoteUpdatedAt = _parseDateTimeValue(remote['updatedAt']);
    if (localUpdatedAt == null || remoteUpdatedAt == null) {
      return false;
    }

    return localUpdatedAt.isAfter(remoteUpdatedAt) ||
        remoteUpdatedAt.isAfter(localUpdatedAt);
  }

  Future<void> _recordTimestampTiebreakHistory({
    required String tableName,
    required int localId,
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required Map<String, dynamic> base,
  }) async {
    final fieldStrategies = mergeStrategiesForTable(tableName);
    if (fieldStrategies.isEmpty) return;

    for (final entry in fieldStrategies.entries) {
      if (!_isTimestampTiebreakWin(
        strategyEntry: entry,
        local: local,
        remote: remote,
        base: base,
      )) {
        continue;
      }

      final fieldName = entry.key;
      final localValue = local[fieldName];
      final remoteValue = remote[fieldName];
      final localUpdatedAt = _parseDateTimeValue(local['updatedAt']);
      final remoteUpdatedAt = _parseDateTimeValue(remote['updatedAt']);
      final localWins = localUpdatedAt != null &&
          remoteUpdatedAt != null &&
          localUpdatedAt.isAfter(remoteUpdatedAt);

      final winningValue = localWins ? localValue : remoteValue;
      final discardedValue = localWins ? remoteValue : localValue;

      await store.saveFieldConflictHistory(
        recordTable: tableName,
        recordLocalId: localId,
        fieldName: fieldName,
        discardedValueJson: jsonEncode(discardedValue),
        winningValueJson: jsonEncode(winningValue),
        localUpdatedAt: localUpdatedAt,
        remoteUpdatedAt: remoteUpdatedAt,
      );
    }
  }

  Future<void> _pushChanges() async {
    // ── One-time legacy recovery ────────────────────────────────────────
    // Rows dropped only because a retryable failure exhausted the old
    // 5-attempt cap are reset to pending once per process. Idempotent: a
    // later run has nothing left to match and resets 0 rows. Runs BEFORE the
    // pending guard so a queue that only contains dropped (terminal) rows is
    // still recovered and pushed on the same cycle.
    if (!_legacyRetryRecoveryDone) {
      _legacyRetryRecoveryDone = true;
      final recovered = await store.recoverRetryableTerminalRows();
      if (recovered > 0) {
        debugPrint(
            '[SYNC-RECOVERY] Recovered $recovered terminal retryable rows');
      }
    }

    final pending = await store.loadPendingQueue();
    if (pending.isEmpty) {
      return;
    }

    // ── Permanent diagnostics: pending scheme_of_work visibility ────────
    // Logs how many scheme_of_work entries are pending and how many are due
    // (out of cooldown) so a stuck push ("All N pending entries are in
    // cooldown — skipping push") is diagnosable from the logs alone.
    // Logging only — no behavior change.
    final sowPending = pending
        .where((e) => e.queueTable == 'scheme_of_work')
        .toList();
    if (sowPending.isNotEmpty) {
      final sowNow = DateTime.now();
      final sowDue = sowPending
          .where((e) =>
              e.nextRetryAt == null || !e.nextRetryAt!.isAfter(sowNow))
          .length;
      debugPrint('[SOW-PUSH] pending scheme_of_work entries: '
          '${sowPending.length}, due: $sowDue');
    }

    final sorted = [...pending]..sort(_compareQueueEntries);
    final batches = <SyncPushBatch>[];
    // Entries actually sent. Entries resolved client-side (an UPDATE
    // superseded by a pending INSERT, or a DELETE with no server row) are
    // marked terminal and excluded, keeping batches and results aligned.
    final sentEntries = <SyncQueueData>[];
    // Payload actually sent for each entry (after server_id injection,
    // UPDATE→INSERT conversion, self-heal, and local_id injection) so the
    // [SOW-PUSH-FAIL] diagnostics can log the exact bytes that went out.
    final sentPayloads = <int, Map<String, dynamic>>{};
    final config = await store.loadSecurityConfig();

    // ── Per-entry cooldown filter ───────────────────────────────────────
    // Entries still in their retry cooldown (next_retry_at in the future)
    // stay pending but are NOT pushed this cycle; they are automatically
    // reconsidered on the next launch/manual sync once the cooldown elapses.
    // If every pending entry is in cooldown, skip the remote push entirely.
    final now = DateTime.now();
    final toPush = sorted
        .where((e) => e.nextRetryAt == null || !e.nextRetryAt!.isAfter(now))
        .toList();
    if (toPush.isEmpty) {
      debugPrint('[PUSH-QUEUE] All ${sorted.length} pending entries are in '
          'cooldown — skipping push');
      return;
    }

    debugPrint('[PUSH-QUEUE] Pending sync entries: ${sorted.length} '
        '(${toPush.length} due for push)');

    for (final entry in toPush) {
      var payload = _decodePayload(entry.payload);
      debugPrint('[PUSH-QUEUE] Entry ${entry.id}: '
          'table=${entry.queueTable}, '
          'operation=${entry.operation}, '
          'localId=${entry.recordLocalId}, '
          'attempts=${entry.attempts}');

      // ── Stale-INSERT recovery ──────────────────────────────────────────
      // If the local record already has a serverId but the queue entry says
      // INSERT, the previous push succeeded (row created on server, UUID
      // stored locally via _updateLocalServerId) but the cleanup
      // (saveSyncedRecord + removeQueueEntry) was interrupted by a crash.
      //
      // Without this check, the stale INSERT re-pushes as a plain INSERT
      // without a server_id, causing the server to create a duplicate row.
      //
      // Fix: detect the stale INSERT, inject the server_id into the payload,
      // and change the operation to UPDATE. The sync-push edge function then
      // uses upsert().onConflict('server_id') instead of plain .insert().
      String effectiveOperation = entry.operation;
      if (effectiveOperation == 'INSERT') {
        final serverId = await _getServerIdForQueueEntry(db, entry);
        if (serverId != null && serverId.isNotEmpty) {
          debugPrint(
            '[PUSH-DIAG] Stale INSERT detected for ${entry.queueTable} '
            'localId=${entry.recordLocalId}, serverId=$serverId — '
            'injecting server_id, converting to upsert',
          );
          payload['server_id'] = serverId;
          effectiveOperation = 'UPDATE';
        }
      }
      // ── Inject server_id for UPDATE/DELETE entries that lack it ────────
      // DAO-crafted UPDATE payloads (scheme_of_work, lessons, exams) never
      // include server_id, so the server's UPDATE branch rejects them with
      // "missing server_id" and they retry forever — status changes (admin
      // approval, submit-for-approval) and edits never reach other devices.
      if (payload['server_id'] == null &&
          (effectiveOperation == 'UPDATE' || effectiveOperation == 'DELETE')) {
        final serverId = await _getServerIdForQueueEntry(db, entry);
        if (serverId != null && serverId.isNotEmpty) {
          payload['server_id'] = serverId;
        }
      }
      // ── Client-side dead-ends: UPDATE/DELETE with no local server_id ────
      // A local row that never received a server_id can never be UPDATEd or
      // DELETEd server-side: the server's UPDATE branch rejects entries
      // without server_id ("missing server_id") and they retry forever — the
      // stuck production case (lessons localId=62, attempts=8, retryable).
      // Resolve these BEFORE the batch is built:
      //   * DELETE → nothing exists server-side; mark terminal.
      //   * UPDATE + pending INSERT for the same row → the INSERT will own
      //     the server row; the UPDATE is superseded; mark terminal.
      //   * UPDATE, no pending INSERT → convert to a clean INSERT using the
      //     same payload builder the full-table reconciliation uses, so the
      //     entry becomes pushable and idempotent with the sync-push
      //     check-before-insert guard.
      if (payload['server_id'] == null &&
          (effectiveOperation == 'UPDATE' || effectiveOperation == 'DELETE')) {
        if (effectiveOperation == 'DELETE') {
          await store.markQueueTerminalFailure(
            entry.id,
            lastError: 'DELETE skipped — local row has no server_id; '
                'nothing to delete server-side',
          );
          debugPrint('[PUSH-QUEUE] Entry ${entry.id}: DELETE for '
              '${entry.queueTable} localId=${entry.recordLocalId} has no '
              'server_id — marked terminal (nothing to delete server-side)');
          continue;
        }
        // ── UPDATE ──
        final hasPendingInsert = await db.syncQueueDao.hasPendingInsertFor(
          entry.queueTable,
          entry.recordLocalId,
        );
        if (hasPendingInsert) {
          await store.markQueueTerminalFailure(
            entry.id,
            lastError: 'UPDATE superseded by pending INSERT — '
                'server_id not yet assigned',
          );
          debugPrint('[PUSH-QUEUE] Entry ${entry.id}: UPDATE for '
              '${entry.queueTable} localId=${entry.recordLocalId} has no '
              'server_id and a pending INSERT exists — marked terminal '
              '(the INSERT will create the server row)');
          continue;
        }
        final insertPayload = await _buildInsertPayloadForQueuedUpdate(
          entry,
          effectiveSchoolId: schoolId,
        );
        if (insertPayload != null) {
          // Persist the converted payload so a retry pushes the INSERT and
          // the success-path version snapshot matches what was sent.
          await db.syncQueueDao.updateEntryPayload(entry.id, insertPayload);
          payload = insertPayload;
          effectiveOperation = 'INSERT';
          debugPrint('[PUSH-QUEUE] Entry ${entry.id}: converted UPDATE → '
              'INSERT for ${entry.queueTable} '
              'localId=${entry.recordLocalId} (local row has no server_id '
              'and no pending INSERT) — clean INSERT is idempotent with the '
              'sync-push check-before-insert guard');
        } else {
          debugPrint('[PUSH-QUEUE] Entry ${entry.id}: UPDATE for '
              '${entry.queueTable} localId=${entry.recordLocalId} has no '
              'server_id and no clean INSERT payload could be built (local '
              'row missing or FK unresolvable) — leaving unchanged');
        }
      }
      // ── Self-heal: progress_logs INSERTs must carry event_date ────────
      // Older queue entries (created before the payload included event_date)
      // fail server-side with "null value in column \"event_date\" ...
      // violates not-null constraint" and retry forever. Inject the ACTUAL
      // local row's eventDate so the entry succeeds without any server
      // schema change. Only INSERTs need this — UPDATEs never touch
      // event_date so the original server value is preserved.
      if (entry.queueTable == 'progress_logs' &&
          effectiveOperation == 'INSERT' &&
          !payload.containsKey('event_date')) {
        final row = await (db.select(db.progressLogs)
              ..where((t) => t.id.equals(entry.recordLocalId)))
            .getSingleOrNull();
        if (row != null) {
          payload['event_date'] = row.eventDate.toUtc().toIso8601String();
          debugPrint(
            '[PUSH-DIAG] Injected event_date=${payload['event_date']} for '
            'progress_logs entry ${entry.id} (localId=${entry.recordLocalId})',
          );
        }
      }
      // ───────────────────────────────────────────────────────────────────

      // ── Self-heal: scheme_of_work term must be lowercase ──────────────
      // The server CHECK constraint scheme_of_work_term_check accepts only
      // 'first' / 'second' / 'third'. Older queue entries queued with
      // title-case terms ('First') are rejected with "violates check
      // constraint" and retry forever. Normalise the term in the payload AND
      // persist the fix so this push succeeds and any retry pushes the
      // corrected value (fixes already-pending entries on the next sync).
      if (entry.queueTable == 'scheme_of_work' &&
          payload.containsKey('term')) {
        final rawTerm = payload['term'];
        if (rawTerm is String) {
          final normalised = normalizeSowTermForServer(rawTerm);
          if (normalised != rawTerm) {
            payload['term'] = normalised;
            await db.syncQueueDao.updateEntryPayload(entry.id, payload);
            debugPrint('[SOW-PUSH] Normalised term from "$rawTerm" to '
                '"$normalised" for entry ${entry.id}');
          }
        }
      }
      // Inject local_id so the server can echo it back in the results
      // array, enabling the client to match responses to entries.
      payload['local_id'] = entry.recordLocalId;
      // DIAG: Log the payload BEFORE compression to verify local_id was injected
      debugPrint('[PUSH-DIAG] Pre-compress payload for entry ${entry.id} '
          '(table=${entry.queueTable}, op=$effectiveOperation): '
          'local_id=${payload['local_id']}, '
          'payload_keys=${payload.keys.join(', ')}');
      // Compress payload for 2G/3G optimization before pushing.
      final compressed = PayloadCompressor.compress(payload);
      // DIAG: Log the compressed payload keys to verify short-key compression
      debugPrint('[PUSH-DIAG] Compressed payload for entry ${entry.id}: '
          'compressed_keys=${compressed.keys.join(', ')}');
      batches.add(
        SyncPushBatch(
          table: entry.queueTable,
          operation: effectiveOperation,
          record: compressed,
        ),
      );
      sentEntries.add(entry);
      sentPayloads[entry.id] = payload;
    }

    // Every pending entry may have been resolved client-side (superseded
    // UPDATEs, DELETEs with no server row) — nothing left to send.
    if (batches.isEmpty) {
      return;
    }

    final response = await remoteApi.pushChanges(
      batches: batches,
      deviceId: config.currentDeviceId,
    );

    // Pair each server result to the entry that produced it BY INDEX: the
    // sync-push edge function processes changes in order and returns exactly
    // one result per change, so results[i] belongs to sentEntries[i]. Key by
    // '<table>:<localId>' so numeric ids from different tables (subjects,
    // lessons, exams, scheme_of_work each auto-increment independently) never
    // collide — a bare local_id map silently assigned one table's result (and
    // its server_id) to every entry sharing the same numeric id.
    final resultsByTableAndLocalId = <String, SyncPushResult>{};
    final paired = sentEntries.length < response.results.length
        ? sentEntries.length
        : response.results.length;
    for (var i = 0; i < paired; i++) {
      resultsByTableAndLocalId[
          '${sentEntries[i].queueTable}:${sentEntries[i].recordLocalId}'] =
          response.results[i];
    }
    if (response.results.length != sentEntries.length) {
      debugPrint(
        '[PUSH-RESULT] WARNING: result count ${response.results.length} '
        '!= entry count ${sentEntries.length} — index pairing may be '
        'misaligned',
      );
    }

    for (final entry in sentEntries) {
      final result = resultsByTableAndLocalId[
          '${entry.queueTable}:${entry.recordLocalId}'];

      debugPrint('[PUSH-RESULT] Entry ID: ${entry.id}, '
          'Table: ${entry.queueTable}, Operation: ${entry.operation}, '
          'Attempts: ${entry.attempts}');

      if (result == null) {
        // ── Defensive: no server result for this entry ──────────────
        // The server can reject an entry before echoing local_id (returning
        // local_id=0) or the response can be truncated. The failure cannot be
        // classified, so it is NEVER marked terminal from the attempt count
        // alone — increment attempts and schedule a retry cooldown instead.
        final nextAttempts = entry.attempts + 1;
        debugPrint('[PUSH-RESULT] No result returned from server for this entry'
            ' (attempt $nextAttempts) — scheduling retry cooldown');
        final backoffSeconds = _retryBackoffSeconds(nextAttempts);
        await store.markQueueAttempt(
          entry.id,
          nextRetryAt: DateTime.now().add(Duration(seconds: backoffSeconds)),
        );
        _setState(SyncState.backoff);
        continue;
      }

      debugPrint('[PUSH-RESULT] Status: "${result.status}", '
          'ServerId: "${result.serverId}", Retryable: ${result.retryable}');

      // DIAG: Log whether the status will pass the success check
      final isSuccess = (result.status == 'created' ||
          result.status == 'updated' ||
          result.status == 'deleted' ||
          result.status == 'skipped');
      debugPrint('[PUSH-DIAG] Entry ${entry.id}: status="${result.status}", '
          'isSuccess=$isSuccess, '
          'serverId="${result.serverId}", '
          'deadChecks={'
          'created: ${result.status == 'created'}, '
          'updated: ${result.status == 'updated'}, '
          'deleted: ${result.status == 'deleted'}, '
          'skipped: ${result.status == 'skipped'}}');

      if (result.status == 'created' ||
          result.status == 'updated' ||
          result.status == 'deleted' ||
          result.status == 'skipped') {
        // ── Post-push bookkeeping ──────────────────────────────────
        // 1. Update the local record's serverId if the server returned one
        //    (especially important for INSERTs where the server generates the UUID).
        // 2. Save a version_hash snapshot so the merge engine has a base for
        //    future sync comparisons.
        if (result.serverId != null && result.serverId!.isNotEmpty) {
          await _updateLocalServerId(
            tableName: entry.queueTable,
            localId: entry.recordLocalId,
            serverId: result.serverId!,
          );
        }
        // Build a snapshot from the original payload to record in version_hashes.
        final payload = _decodePayload(entry.payload);
        await store.saveSyncedRecord(
          tableName: entry.queueTable,
          localId: entry.recordLocalId,
          snapshot: payload,
        );
        // ───────────────────────────────────────────────────────────
        await store.removeQueueEntry(entry.id);
        continue;
      }

      // ── Permanent diagnostics: scheme_of_work push failures ──────────
      // Logs the raw server response for every failed scheme_of_work push
      // (status not created/updated/deleted/skipped) so stuck entries can
      // be diagnosed from the logs alone. Logging only — the
      // retry/cooldown flow below is untouched.
      if (entry.queueTable == 'scheme_of_work') {
        final errorMessageText = result.errorMessage == null
            ? ''
            : ', errorMessage="${result.errorMessage}"';
        debugPrint('[SOW-PUSH-FAIL] Entry id=${entry.id}, '
            'operation=${entry.operation}, '
            'localId=${entry.recordLocalId}, '
            'attempts=${entry.attempts}, '
            'nextRetryAt=${entry.nextRetryAt}');
        debugPrint('[SOW-PUSH-FAIL] Sent payload: '
            '${sentPayloads[entry.id]}');
        debugPrint('[SOW-PUSH-FAIL] Server result: '
            'local_id=${result.localId}, '
            'server_id=${result.serverId}, '
            'status="${result.status}", '
            'retryable=${result.retryable}$errorMessageText');
      }

      debugPrint('[PUSH-RESULT] Entry ${entry.id} not successful — '
          'retryable=${result.retryable}, attempts=${entry.attempts}');
      final nextAttempts = entry.attempts + 1;
      final failureMessage = result.errorMessage ??
          'Sync push failed for ${entry.queueTable} ${entry.operation}';

      // ── Emergency exemption ────────────────────────────────────────
      // Emergency entries must NEVER be marked terminal on push failure.
      // They are the survival guarantee for force-logout/deactivation:
      // _applyCreditState() deletes only isEmergency==false rows, and
      // pendingEntries() filters isTerminal==false, so marking an emergency
      // entry terminal would silently drop it from the queue. Instead it
      // stays pending and is pushed again on the next cycle (no per-entry
      // cooldown — emergency entries are urgent).
      if (entry.isEmergency) {
        await store.markQueueAttempt(entry.id);
        debugPrint(
          '[PUSH-RESULT] Emergency entry ${entry.id} NOT marked terminal '
          '(attempt $nextAttempts) — retained in pending queue',
        );
        _setState(SyncState.backoff);
      } else if (!result.retryable) {
        // ── Non-retryable: server indicated this entry will NEVER succeed
        // (e.g. admin-table push from a non-admin user, or a non-syncable
        // table). Preserve it as terminal so the failure stays visible.
        await store.markQueueAttempt(entry.id);
        debugPrint(
          '[PUSH-RESULT] Marking non-retryable queue entry terminal '
          '(id=${entry.id}, table=${entry.queueTable}, '
          'operation=${entry.operation})',
        );
        await store.markQueueTerminalFailure(
          entry.id,
          lastError: failureMessage,
        );
      } else {
        // ── Retryable: NEVER terminal from the attempt count alone. Increment
        // attempts, schedule next_retry_at with exponential backoff, and keep
        // the entry pending — it is automatically reconsidered after the
        // cooldown elapses on a later launch/manual sync.
        final backoffSeconds = _retryBackoffSeconds(nextAttempts);
        final nextRetryAt = DateTime.now().add(Duration(seconds: backoffSeconds));
        await store.markQueueAttempt(
          entry.id,
          nextRetryAt: nextRetryAt,
        );
        debugPrint('[PUSH-RESULT] Entry ${entry.id} is retryable '
            '(attempt $nextAttempts) — next retry at $nextRetryAt, '
            'entering backoff');
        _setState(SyncState.backoff);
      }
    }
  }

  /// Exponential retry backoff for a failed push attempt: 30s * 2^(n-1),
  /// capped at 1 hour, where [attemptNumber] is the 1-based attempt count.
  static int _retryBackoffSeconds(int attemptNumber) {
    var exponent = attemptNumber - 1;
    if (exponent < 0) exponent = 0;
    if (exponent > 7) exponent = 7;
    final seconds = 30 * (1 << exponent);
    return seconds > 3600 ? 3600 : seconds;
  }

  /// Updates the [serverId] column on a local record after a successful push.
  Future<void> _updateLocalServerId({
    required String tableName,
    required int localId,
    required String serverId,
  }) async {
    switch (tableName) {
      case 'lessons':
        await (db.update(db.lessons)..where((t) => t.id.equals(localId)))
            .write(LessonsCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'exams':
        await (db.update(db.exams)..where((t) => t.id.equals(localId)))
            .write(ExamsCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'scheme_of_work':
        await (db.update(db.schemeOfWork)..where((t) => t.id.equals(localId)))
            .write(SchemeOfWorkCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'vault_items':
        await (db.update(db.vaultItems)..where((t) => t.id.equals(localId)))
            .write(VaultItemsCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'teachers':
        await (db.update(db.teachers)..where((t) => t.localId.equals(localId)))
            .write(TeachersCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'schools':
        await (db.update(db.schools)..where((t) => t.localId.equals(localId)))
            .write(SchoolsCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'progress_logs':
        await (db.update(db.progressLogs)..where((t) => t.id.equals(localId)))
            .write(ProgressLogsCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      case 'subjects':
        await (db.update(db.subjects)..where((t) => t.id.equals(localId)))
            .write(SubjectsCompanion(
          serverId: Value(serverId),
          updatedAt: Value(DateTime.now()),
        ));
        break;
      // Extend with other tables as needed.
      default:
        break;
    }
  }

  Future<void> _applyCreditState() async {
    final now = DateTime.now();
    if (!accountActive) {
      _setState(SyncState.emergencySave);
      await securityService.clearSessionKey();
      await (db.delete(db.syncQueue)..where((t) => t.isEmergency.equals(false)))
          .go();
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

    // Fetch credit state from server and reset local credits
    await _syncCreditState();

    _setState(SyncState.replayingRealtime);
    final config = await store.loadSecurityConfig();
    await _replayRealtimeEvents(config.lastRealtimeEventId);
    _setState(SyncState.idle);
  }

  /// Fetches credit state from server and resets local credits.
  Future<void> _syncCreditState() async {
    try {
      final response = await remoteApi.fetchCreditState();
      if (response != null) {
        await db.securityConfigDao.updateConfig(
          offlineCredits: response['offlineCredits'] as int? ?? 3,
          creditServerCounter: response['creditServerCounter'] as int? ?? 0,
          creditSpentIdsLocal: (() {
            final spentIds = response['spentIds'];
            if (spentIds is String) return spentIds;
            if (spentIds is List) return jsonEncode(spentIds);
            return '[]';
          })(),
        );
      }
    } catch (e) {
      // Log but don't fail the sync cycle
      debugPrint('Failed to sync credit state: $e');
    }
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
      latestEventId =
          event.eventId > latestEventId ? event.eventId : latestEventId;
      await _handleRealtimeEvent(event);
    }

    await store.updateSecurityConfig(lastRealtimeEventId: latestEventId);
  }

  Future<void> _handleRealtimeEvent(SyncRealtimeEvent event) async {
    final recordId = _readInt(event.payload, 'localId') ??
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
    // Decompress early so localId is available for error logging.
    final decompressed = PayloadCompressor.decompress(change.row);
    final remote = _normalizeRecord(decompressed);
    int localId;
    String? baseHash;
    Map<String, dynamic> local;

    // ── Branch by table: derive a real Drift localId ─────────────────
    // Tables that have a server-side local_id (lessons, exams) can use
    // the existing _readInt chain from the remote payload.
    // Tables without a server-side local_id (teachers, schools) must
    // resolve the localId by looking up the existing Drift row via
    // serverId (READ ONLY — no write until after three-way merge).
    if (change.table == 'teachers') {
      final serverId =
          remote['server_id'] as String? ?? remote['id'] as String?;
      if (serverId == null || serverId.isEmpty) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: skipping teacher — no serverId',
        );
        return;
      }

      // Read-only lookup: find existing teacher by serverId.
      final existing = await (db.select(db.teachers)
            ..where((t) => t.serverId.equals(serverId)))
          .get();

      if (existing.isEmpty) {
        // NEW teacher — upsert remote directly, write to versionHashes,
        // skip three-way merge (MergeEngine returns remote as-is when
        // there is no base record).
        final newLocalId = await _upsertTeacherFromSync(remote);
        if (newLocalId == null) {
          debugPrint(
            '[SYNC] _mergeRemoteChange: skipping new teacher '
            '(school not yet synced) — will retry on next pull',
          );
          return;
        }
        await store.saveSyncedRecord(
          tableName: 'teachers',
          localId: newLocalId,
          snapshot: remote,
        );
        _setState(SyncState.merging);
        return;
      }

      // EXISTING teacher — use real localId for versionHashes ops.
      // Pick the lowest localId if duplicates exist (defensive — mirrors
      // the _deduplicateTeachers strategy of keeping the oldest row).
      if (existing.length > 1) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: ${existing.length} local rows for '
          'teacher serverId=$serverId — using lowest localId',
        );
        existing.sort((a, b) => a.localId.compareTo(b.localId));
      }
      localId = existing.first.localId;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    } else if (change.table == 'schools') {
      final serverId =
          remote['server_id'] as String? ?? remote['id'] as String?;
      if (serverId == null || serverId.isEmpty) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: skipping school — no serverId',
        );
        return;
      }

      // Read-only lookup: find existing school by serverId.
      final existing = await (db.select(db.schools)
            ..where((s) => s.serverId.equals(serverId)))
          .get();

      if (existing.isEmpty) {
        // NEW school — upsert remote directly, write to versionHashes,
        // skip three-way merge (MergeEngine returns remote as-is when
        // there is no base record).
        final newLocalId = await _upsertSchoolFromSync(remote);
        if (newLocalId == null) {
          debugPrint(
            '[SYNC] _mergeRemoteChange: skipping new school — '
            'could not resolve serverId',
          );
          return;
        }
        await store.saveSyncedRecord(
          tableName: 'schools',
          localId: newLocalId,
          snapshot: remote,
        );
        _setState(SyncState.merging);
        return;
      }

      // EXISTING school — use real localId for versionHashes ops.
      // Pick the lowest localId if duplicates exist (defensive).
      if (existing.length > 1) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: ${existing.length} local rows for '
          'school serverId=$serverId — using lowest localId',
        );
        existing.sort((a, b) => a.localId.compareTo(b.localId));
      }
      localId = existing.first.localId;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    } else if (change.table == 'lessons') {
      final serverId =
          remote['server_id'] as String? ?? remote['id'] as String?;
      if (serverId == null || serverId.isEmpty) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: skipping lesson — no serverId',
        );
        return;
      }

      // Read-only lookup: find existing lesson by serverId.
      final existing = await (db.select(db.lessons)
            ..where((t) => t.serverId.equals(serverId)))
          .get();

      if (existing.isEmpty) {
        // NEW lesson — upsert remote directly, write to versionHashes,
        // skip three-way merge.
        final newLocalId = await _upsertLessonFromSync(remote);
        if (newLocalId == null) {
          debugPrint(
            '[SYNC] _mergeRemoteChange: skipping new lesson — '
            'upsert returned null',
          );
          return;
        }
        await store.saveSyncedRecord(
          tableName: 'lessons',
          localId: newLocalId,
          snapshot: remote,
        );
        _setState(SyncState.merging);
        return;
      }

      // EXISTING lesson — use real localId for versionHashes ops.
      if (existing.length > 1) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: ${existing.length} local rows for '
          'lesson serverId=$serverId — using lowest localId',
        );
        existing.sort((a, b) => a.id.compareTo(b.id));
      }
      localId = existing.first.id;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    } else if (change.table == 'exams') {
      final serverId =
          remote['server_id'] as String? ?? remote['id'] as String?;
      if (serverId == null || serverId.isEmpty) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: skipping exam — no serverId',
        );
        return;
      }

      // Read-only lookup: find existing exam by serverId.
      final existing = await (db.select(db.exams)
            ..where((t) => t.serverId.equals(serverId)))
          .get();

      if (existing.isEmpty) {
        // NEW exam — upsert remote directly.
        final newLocalId = await _upsertExamFromSync(remote);
        if (newLocalId == null) {
          debugPrint(
            '[SYNC] _mergeRemoteChange: skipping new exam — '
            'upsert returned null',
          );
          return;
        }
        await store.saveSyncedRecord(
          tableName: 'exams',
          localId: newLocalId,
          snapshot: remote,
        );
        _setState(SyncState.merging);
        return;
      }

      // EXISTING exam — use real localId for versionHashes ops.
      if (existing.length > 1) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: ${existing.length} local rows for '
          'exam serverId=$serverId — using lowest localId',
        );
        existing.sort((a, b) => a.id.compareTo(b.id));
      }
      localId = existing.first.id;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    } else if (change.table == 'subjects') {
      final serverId =
          remote['server_id'] as String? ?? remote['id'] as String?;
      if (serverId == null || serverId.isEmpty) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: skipping subject — no serverId',
        );
        return;
      }

      // Read-only lookup: find existing subject by serverId.
      final existing = await (db.select(db.subjects)
            ..where((t) => t.serverId.equals(serverId)))
          .get();

      if (existing.isEmpty) {
        // NEW subject — upsert remote directly.
        final newLocalId = await _upsertSubjectFromSync(remote);
        if (newLocalId == null) {
          debugPrint(
            '[SYNC] _mergeRemoteChange: skipping new subject — '
            'upsert returned null',
          );
          return;
        }
        await store.saveSyncedRecord(
          tableName: 'subjects',
          localId: newLocalId,
          snapshot: remote,
        );
        _setState(SyncState.merging);
        return;
      }

      // EXISTING subject — use real localId for versionHashes ops.
      if (existing.length > 1) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: ${existing.length} local rows for '
          'subject serverId=$serverId — using lowest localId',
        );
        existing.sort((a, b) => a.id.compareTo(b.id));
      }
      localId = existing.first.id;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    } else if (change.table == 'scheme_of_work') {
      final serverId =
          remote['server_id'] as String? ?? remote['id'] as String?;
      if (serverId == null || serverId.isEmpty) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: skipping scheme_of_work — no serverId',
        );
        return;
      }

      // Read-only lookup: find existing scheme_of_work by serverId.
      final existing = await (db.select(db.schemeOfWork)
            ..where((t) => t.serverId.equals(serverId)))
          .get();

      if (existing.isEmpty) {
        // NEW scheme_of_work — upsert remote directly, write to
        // versionHashes, skip three-way merge.
        final newLocalId = await _upsertSchemeOfWorkFromSync(remote);
        if (newLocalId == null) {
          debugPrint(
            '[SYNC] _mergeRemoteChange: skipping new scheme_of_work — '
            'upsert returned null (unresolved FK)',
          );
          return;
        }
        await store.saveSyncedRecord(
          tableName: 'scheme_of_work',
          localId: newLocalId,
          snapshot: remote,
        );
        _setState(SyncState.merging);
        return;
      }

      // EXISTING scheme_of_work — use real localId for versionHashes ops.
      if (existing.length > 1) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: ${existing.length} local rows for '
          'scheme_of_work serverId=$serverId — using lowest localId',
        );
        existing.sort((a, b) => a.id.compareTo(b.id));
      }
      localId = existing.first.id;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    } else if (change.table == 'payment_events') {
      // payment_events has no serverId column; the unique identifier is
      // transactionReference. Look up the existing local row by this key.
      final transactionReference = remote['transaction_reference'] as String?;
      if (transactionReference == null || transactionReference.isEmpty) {
        debugPrint(
          '[SYNC] _mergeRemoteChange: skipping payment_event — '
          'no transactionReference',
        );
        return;
      }

      // Read-only lookup: find existing payment_event by transactionReference.
      final existing = await (db.select(db.paymentEvents)
            ..where((t) => t.transactionReference.equals(transactionReference)))
          .get();

      if (existing.isEmpty) {
        // NEW payment_event — upsert remote directly, write to
        // versionHashes, skip three-way merge.
        final newLocalId = await _upsertPaymentEventFromSync(remote);
        if (newLocalId == null) {
          debugPrint(
            '[SYNC] _mergeRemoteChange: skipping new payment_event — '
            'upsert returned null',
          );
          return;
        }
        await store.saveSyncedRecord(
          tableName: 'payment_events',
          localId: newLocalId,
          snapshot: remote,
        );
        _setState(SyncState.merging);
        return;
      }

      // EXISTING payment_event — use real localId for versionHashes ops.
      localId = existing.first.id;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    } else {
      // For all remaining tables (progress_logs, vault_items) the
      // remote payload may contain a real local_id — fall back to the
      // existing chain.
      localId = _readInt(remote, 'localId') ??
          _readInt(remote, 'local_id') ??
          _readInt(remote, 'id') ??
          0;
      local = await store.loadLocalRecord(change.table, localId) ?? const {};
      baseHash = await _loadBaseHash(change.table, localId);
    }
    final base =
        await store.loadBaseRecordByHash(change.table, localId, baseHash);

    try {
      final result = await _threeWayMerge(local, remote, change.table, base);

      if (baseHash == null) {
        _setState(SyncState.savingConflicts);
        await store.saveConflict(
          recordType: change.table,
          recordLocalId: localId,
          conflictingFields: local.keys.toList(),
          localValue: jsonEncode(local),
          remoteValue: jsonEncode(remote),
          resolution: MergeResolution.remote.name,
          notified: false,
        );
      } else if (result.conflictingFields.isNotEmpty) {
        _setState(SyncState.savingConflicts);
        await store.saveConflict(
          recordType: change.table,
          recordLocalId: localId,
          conflictingFields: result.conflictingFields,
          localValue: jsonEncode(local),
          remoteValue: jsonEncode(remote),
          resolution: result.resolution.name,
          notified: false,
        );
      }

      if (base != null) {
        await _recordTimestampTiebreakHistory(
          tableName: change.table,
          localId: localId,
          local: local,
          remote: remote,
          base: base,
        );
      }

      await store.saveSyncedRecord(
        tableName: change.table,
        localId: localId,
        snapshot: result.merged,
      );

      // Write the three-way-merged result back to the data table.
      // For teachers and schools, result.merged may differ from raw
      // remote after conflict resolution; this call ensures the data
      // table reflects the merge output, not the raw remote payload.
      // For all other tables, versionHashes is the single source of
      // truth and no data-table upsert is needed.
      if (change.table == 'teachers') {
        await _upsertTeacherFromSync(result.merged);
      } else if (change.table == 'schools') {
        await _upsertSchoolFromSync(result.merged);
      } else if (change.table == 'lessons') {
        await _upsertLessonFromSync(result.merged);
      } else if (change.table == 'exams') {
        await _upsertExamFromSync(result.merged);
      } else if (change.table == 'subjects') {
        await _upsertSubjectFromSync(result.merged);
      } else if (change.table == 'scheme_of_work') {
        await _upsertSchemeOfWorkFromSync(result.merged);
      } else if (change.table == 'payment_events') {
        await _upsertPaymentEventFromSync(result.merged);
      }

      _setState(SyncState.merging);
    } catch (e, st) {
      debugPrint(
        '[SYNC] ERROR merging record: table=${change.table}, '
        'localId=$localId, error=$e',
      );
      await Sentry.captureException(
        e,
        stackTrace: st,
      );
      // One record is skipped; the rest of the pull cycle continues.
    }
  }

  /// Upserts a teacher row from synced remote data into the local Drift
  /// [teachers] table. The [merged] map uses snake_case keys from Supabase.
  ///
  /// Returns the Drift [localId] of the upserted row, or `null` if the
  /// upsert was skipped (e.g. no serverId, or the teacher's school hasn't
  /// been synced yet).
  Future<int?> _upsertTeacherFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ?? merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint(
          '[sync] _upsertTeacherFromSync skipped: no serverId in $merged');
      return null;
    }

    // Look up existing teacher by serverId
    final existing = await (db.select(db.teachers)
          ..where((t) => t.serverId.equals(serverId)))
        .get();

    // Map snake_case remote fields to Drift column values
    String? strVal(String key) => merged[key] as String?;
    bool boolVal(String key) => merged[key] == true || merged[key] == 'true';
    int? intVal(String key) => _readInt(merged, key);
    DateTime? dateVal(String key) {
      final raw = merged[key];
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final email = strVal('email') ?? '';
    final teacherName = strVal('teacher_name') ?? '';
    final role = strVal('role') ?? 'teacher';
    final schoolServerId = strVal('school_id');
    final isActive = boolVal('is_active');
    final forcePasswordReset = boolVal('force_password_reset');
    final passwordHashVersion = intVal('password_hash_version') ?? 1;
    final tempPassword = strVal('temp_password');
    final schoolKeyWrapped =
        strVal('school_key_wrapped') ?? strVal('school_master_key_wrapped');
    final salt = strVal('salt');
    final currentDeviceId = strVal('current_device_id');
    final isDeleted = boolVal('is_deleted');
    final createdAt = dateVal('created_at') ?? DateTime.now();
    final updatedAt = dateVal('updated_at') ?? DateTime.now();
    final lastModifiedBy = strVal('last_modified_by');

    // Resolve schoolLocalId from schoolServerId.
    // If the remote teacher has no schoolServerId, or the school isn't yet
    // synced locally, we leave schoolLocalId absent rather than guessing —
    // a silent wrong-school assignment caused the same bug class earlier with
    // schoolsDao.get().
    int? resolvedSchoolLocalId;
    if (schoolServerId != null) {
      final schoolRow = await (db.select(db.schools)
            ..where((s) => s.serverId.equals(schoolServerId)))
          .getSingleOrNull();
      resolvedSchoolLocalId = schoolRow?.localId;
    }
    if (resolvedSchoolLocalId == null || resolvedSchoolLocalId == 0) {
      await _queueDeferredTeacher(merged);
      debugPrint(
        '[sync] _upsertTeacherFromSync: no local school found for '
        'schoolServerId=$schoolServerId (teacher $serverId). '
        'schoolLocalId left absent; will resolve on next pull.',
      );
    }

    debugPrint(
      '[sync] _upsertTeacherFromSync: serverId=$serverId, '
      'forcePasswordReset=$forcePasswordReset, '
      'tempPassword=${tempPassword != null ? '(set)' : 'null'}, '
      'schoolServerId=$schoolServerId, '
      'resolvedSchoolLocalId=$resolvedSchoolLocalId',
    );

    if (existing.isNotEmpty) {
      // Update existing teacher record
      final existingTeacher = existing.first;
      await (db.update(db.teachers)
            ..where((t) => t.localId.equals(existingTeacher.localId)))
          .write(TeachersCompanion(
        email: Value(email),
        teacherName: Value(teacherName),
        role: Value(role),
        schoolServerId: schoolServerId != null
            ? Value(schoolServerId)
            : const Value.absent(),
        schoolLocalId: resolvedSchoolLocalId != null
            ? Value(resolvedSchoolLocalId)
            : const Value.absent(),
        isActive: Value(isActive),
        forcePasswordReset: Value(forcePasswordReset),
        passwordHashVersion: Value(passwordHashVersion),
        schoolKeyWrapped: schoolKeyWrapped != null
            ? Value(schoolKeyWrapped)
            : const Value.absent(),
        salt: salt != null ? Value(salt) : const Value.absent(),
        currentDeviceId: currentDeviceId != null
            ? Value(currentDeviceId)
            : const Value.absent(),
        tempPassword:
            tempPassword != null ? Value(tempPassword) : const Value.absent(),
        isDeleted: Value(isDeleted),
        updatedAt: Value(updatedAt),
        lastModifiedBy: lastModifiedBy != null
            ? Value(lastModifiedBy)
            : const Value.absent(),
        lastSyncAt: dateVal('last_sync_at') != null
            ? Value(dateVal('last_sync_at')!)
            : const Value.absent(),
        updateCounter: Value(existingTeacher.updateCounter + 1),
      ));
      debugPrint('[sync] _upsertTeacherFromSync: UPDATED teacher $serverId');
      return existingTeacher.localId;
    } else {
      // Insert new teacher record.
      // If resolvedSchoolLocalId is null (school not yet synced locally),
      // skip the INSERT entirely rather than writing an invalid FK of 0,
      // which would throw a foreign-key constraint violation. The teacher
      // will be picked up on the next pull cycle once the school arrives.
      if (resolvedSchoolLocalId == null || resolvedSchoolLocalId == 0) {
        debugPrint(
          '[sync] _upsertTeacherFromSync: SKIP INSERT teacher $serverId — '
          'schoolServerId=$schoolServerId not yet synced locally. '
          'Will retry on next pull.',
        );
        await Sentry.captureException(
          Exception(
            'Deferred teacher INSERT (school not synced): '
            'serverId=$serverId, schoolServerId=$schoolServerId',
          ),
        );
        return null;
      }

      final newLocalId = await (db.into(db.teachers).insert(
            TeachersCompanion.insert(
              serverId: Value(serverId),
              email: email,
              teacherName: teacherName,
              role: Value(role),
              schoolLocalId: resolvedSchoolLocalId,
              schoolServerId: schoolServerId != null
                  ? Value(schoolServerId)
                  : const Value.absent(),
              isActive: Value(isActive),
              forcePasswordReset: Value(forcePasswordReset),
              passwordHashVersion: Value(passwordHashVersion),
              schoolKeyWrapped: schoolKeyWrapped != null
                  ? Value(schoolKeyWrapped)
                  : const Value.absent(),
              tempPassword: tempPassword != null
                  ? Value(tempPassword)
                  : const Value.absent(),
              salt: salt != null ? Value(salt) : const Value.absent(),
              currentDeviceId: currentDeviceId != null
                  ? Value(currentDeviceId)
                  : const Value.absent(),
              isDeleted: Value(isDeleted),
              createdAt: Value(createdAt),
              updatedAt: Value(updatedAt),
              lastModifiedBy: lastModifiedBy != null
                  ? Value(lastModifiedBy)
                  : const Value.absent(),
              lastSyncAt: Value(dateVal('last_sync_at')),
            ),
          ));
      debugPrint('[sync] _upsertTeacherFromSync: INSERTED teacher $serverId');
      return newLocalId;
    }
  }

  Future<void> _queueDeferredTeacher(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ?? merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) return;

    try {
      final deferred = await store.loadDeferredTeacherSnapshots();
      for (final snapshot in deferred) {
        try {
          final decoded = jsonDecode(snapshot.snapshotData);
          if (decoded is! Map) continue;
          final queued = Map<String, dynamic>.from(decoded);
          final queuedServerId =
              queued['server_id'] as String? ?? queued['id'] as String?;
          if (queuedServerId == serverId) {
            return;
          }
        } catch (_) {
          // Ignore malformed entries; flush will clean them up if needed.
        }
      }

      await store.saveDeferredTeacherSnapshot(
        snapshot: Map<String, dynamic>.from(merged),
      );
    } catch (e, st) {
      debugPrint('[sync] _queueDeferredTeacher failed for $serverId: $e');
      await Sentry.captureException(
        e,
        stackTrace: st,
      );
    }
  }

  Future<void> _flushDeferredTeachers() async {
    final deferred = await store.loadDeferredTeacherSnapshots();
    if (deferred.isEmpty) return;

    for (final snapshot in deferred) {
      try {
        final decoded = jsonDecode(snapshot.snapshotData);
        if (decoded is! Map) {
          await store.removeDeferredTeacherSnapshot(snapshot.id);
          continue;
        }

        final row = Map<String, dynamic>.from(decoded);
        final localId = await _upsertTeacherFromSync(row);
        if (localId != null) {
          await store.saveSyncedRecord(
            tableName: 'teachers',
            localId: localId,
            snapshot: row,
          );
          await store.removeDeferredTeacherSnapshot(snapshot.id);
        }
      } catch (e, st) {
        debugPrint(
          '[sync] _flushDeferredTeachers failed for snapshot ${snapshot.id}: $e',
        );
        await Sentry.captureException(
          e,
          stackTrace: st,
        );
      }
    }
  }

  /// Upserts a school row from synced remote data into the local Drift
  /// [schools] table via [SchoolsDao.upsertByServerId]. The [merged] map uses
  /// snake_case keys from Supabase.
  ///
  /// This mirrors the pattern used by [_upsertTeacherFromSync] so that remote
  /// changes to the schools table (e.g. subscription_tier updates applied
  /// directly in Supabase) are written into the local Drift table immediately,
  /// not just into synced_records.
  ///
  /// Returns the Drift [localId] of the upserted row, or `null` if the
  /// upsert was skipped (e.g. no serverId).
  Future<int?> _upsertSchoolFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ?? merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint(
          '[sync] _upsertSchoolFromSync skipped: no serverId in $merged');
      return null;
    }

    // Map snake_case remote keys to the parameters expected by upsertByServerId.
    String? strVal(String key) => merged[key] as String?;

    final schoolName = strVal('school_name') ?? '';
    final shortCode = strVal('short_code') ?? '';
    final subscriptionTier = strVal('subscription_tier') ?? 'free';
    final activeCurriculum = strVal('active_curriculum') ?? 'nerdc';
    final activeCurriculumVersion = strVal('active_curriculum_version');
    final totalSeats = _readInt(merged, 'total_seats') ?? 5;
    final schoolMasterKeyWrapped =
        strVal('school_master_key_wrapped') ?? strVal('school_key_wrapped');
    final adminRecoveryEmail = strVal('admin_recovery_email');
    final adminRecoveryEmailVerified =
        merged['admin_recovery_email_verified'] == true ||
            merged['admin_recovery_email_verified'] == 'true';

    // Parse optional DateTime fields (matching the pattern used by dateVal
    // in _upsertTeacherFromSync).
    DateTime? expiryDate;
    final rawExpiry = merged['expiry_date'];
    if (rawExpiry is DateTime) {
      expiryDate = rawExpiry;
    } else if (rawExpiry is String) {
      expiryDate = DateTime.tryParse(rawExpiry);
    }

    final activationCode = strVal('activation_code');

    final school = await db.schoolsDao.upsertByServerId(
      serverId: serverId,
      schoolName: schoolName,
      shortCode: shortCode,
      subscriptionTier: subscriptionTier,
      activeCurriculum: activeCurriculum,
      activeCurriculumVersion: activeCurriculumVersion,
      totalSeats: totalSeats,
      schoolMasterKeyWrapped: schoolMasterKeyWrapped,
      adminRecoveryEmail: adminRecoveryEmail,
      adminRecoveryEmailVerified: adminRecoveryEmailVerified,
      expiryDate: expiryDate,
      activationCode: activationCode,
    );

    debugPrint(
      '[sync] _upsertSchoolFromSync: upserted school $serverId '
      '(tier=$subscriptionTier)',
    );

    return school.localId;
  }

  /// Upserts a lesson row from synced remote data into the local Drift
  /// [lessons] table. The [merged] map uses snake_case keys from Supabase.
  ///
  /// Returns the Drift [localId] of the upserted row, or `null` if the
  /// upsert was skipped (e.g. no serverId).
  ///
  /// Note: [teacherServerId] and [schoolServerId] are text columns with no
  /// local FK constraint, so no foreign-key resolution is required — unlike
  /// teachers/schools which have integer [schoolLocalId] FKs.
  Future<int?> _upsertLessonFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ?? merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint(
          '[sync] _upsertLessonFromSync skipped: no serverId in $merged');
      return null;
    }

    // Look up existing lesson by serverId.
    final existing = await (db.select(db.lessons)
          ..where((t) => t.serverId.equals(serverId)))
        .get();

    // Map snake_case remote fields to Drift column values.
    String? strVal(String key) => merged[key] as String?;
    bool boolVal(String key) => merged[key] == true || merged[key] == 'true';
    int? intVal(String key) => _readInt(merged, key);
    DateTime? dateVal(String key) {
      final raw = merged[key];
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final classLevel = strVal('class_level') ?? '';
    final week = intVal('week') ?? 0;
    final topic = strVal('topic') ?? '';
    final difficulty = strVal('difficulty') ?? '';
    final bloomsVerbs = strVal('blooms_verbs') ?? '';
    final curriculum = strVal('curriculum') ?? '';
    final content = strVal('content') ?? '';
    final contentHash = strVal('content_hash');
    final schemeOfWorkId = strVal('scheme_of_work_id');
    final weekNumber = intVal('week_number');
    final isDeleted = boolVal('is_deleted');
    final lastModifiedBy = strVal('last_modified_by');
    final teacherServerId = strVal('teacher_id') ?? strVal('teacher_server_id');
    final schoolServerId = strVal('school_id') ?? strVal('school_server_id');
    final isUnlocked = boolVal('is_unlocked');
    final status = strVal('status') ?? 'draft';
    final term = strVal('term');
    final createdAt = dateVal('created_at') ?? DateTime.now();
    final updatedAt = dateVal('updated_at') ?? DateTime.now();
    final updateCounter = intVal('update_counter') ?? 0;

    if (existing.isNotEmpty) {
      // Update existing lesson record.
      final existingLesson = existing.first;

      // ── Empty-remote guard ──────────────────────────────────────────────
      // The sync-push Edge Function deletes the `subject` text field from
      // the INSERT payload after resolving it to `subject_id` (a UUID FK on
      // the server). When the client pulls the row back, `subject` is ''
      // or null, which overwrites the valid local subject (e.g. "Mathematics")
      // with ''. This cascading data loss causes duplicate-detection failures
      // downstream because `l.subject == _subject` evaluates `"" == "Mathematics"`
      // → false, so the scheme-of-work screens create duplicate draft lessons
      // on every save.
      //
      final resolvedSubject = await _resolveSubjectNameFromSync(
        merged,
        existingSubject: existingLesson.subject,
      );
      final resolvedClassLevel =
          (classLevel.isEmpty && existingLesson.classLevel.isNotEmpty)
              ? existingLesson.classLevel
              : classLevel;
      final resolvedTopic = (topic.isEmpty && existingLesson.topic.isNotEmpty)
          ? existingLesson.topic
          : topic;

      await (db.update(db.lessons)
            ..where((t) => t.id.equals(existingLesson.id)))
          .write(LessonsCompanion(
        serverId: Value(serverId),
        subject: Value(resolvedSubject),
        classLevel: Value(resolvedClassLevel),
        week: Value(week),
        topic: Value(resolvedTopic),
        difficulty: Value(difficulty),
        bloomsVerbs: Value(bloomsVerbs),
        curriculum: Value(curriculum),
        content: Value(content),
        contentHash:
            contentHash != null ? Value(contentHash) : const Value.absent(),
        schemeOfWorkId: schemeOfWorkId != null
            ? Value(schemeOfWorkId)
            : const Value.absent(),
        weekNumber:
            weekNumber != null ? Value(weekNumber) : const Value.absent(),
        isDeleted: Value(isDeleted),
        lastModifiedBy: lastModifiedBy != null
            ? Value(lastModifiedBy)
            : const Value.absent(),
        teacherServerId: teacherServerId != null
            ? Value(teacherServerId)
            : const Value.absent(),
        schoolServerId: schoolServerId != null
            ? Value(schoolServerId)
            : const Value.absent(),
        isUnlocked: Value(isUnlocked),
        status: Value(status),
        term: term != null ? Value(term) : const Value.absent(),
        updatedAt: Value(updatedAt),
        updateCounter: Value(updateCounter),
      ));
      debugPrint('[sync] _upsertLessonFromSync: UPDATED lesson $serverId');
      return existingLesson.id;
    } else {
      // Insert new lesson record.
      final resolvedSubject = await _resolveSubjectNameFromSync(merged);
      final newLocalId = await (db.into(db.lessons).insert(
            LessonsCompanion.insert(
              serverId: Value(serverId),
              subject: resolvedSubject,
              classLevel: classLevel,
              week: week,
              topic: topic,
              difficulty: difficulty,
              bloomsVerbs: bloomsVerbs,
              curriculum: curriculum,
              content: content,
              contentHash: contentHash != null
                  ? Value(contentHash)
                  : const Value.absent(),
              schemeOfWorkId: schemeOfWorkId != null
                  ? Value(schemeOfWorkId)
                  : const Value.absent(),
              weekNumber:
                  weekNumber != null ? Value(weekNumber) : const Value.absent(),
              isDeleted: Value(isDeleted),
              lastModifiedBy: lastModifiedBy != null
                  ? Value(lastModifiedBy)
                  : const Value.absent(),
              teacherServerId: teacherServerId != null
                  ? Value(teacherServerId)
                  : const Value.absent(),
              schoolServerId: schoolServerId != null
                  ? Value(schoolServerId)
                  : const Value.absent(),
              isUnlocked: Value(isUnlocked),
              status: Value(status),
              term: term != null ? Value(term) : const Value.absent(),
              createdAt: Value(createdAt),
              updatedAt: Value(updatedAt),
            ),
          ));
      debugPrint('[sync] _upsertLessonFromSync: INSERTED lesson $serverId');
      return newLocalId;
    }
  }

  /// Upserts an exam row from synced remote data into the local Drift
  /// [exams] table. The [merged] map uses snake_case keys from Supabase.
  ///
  /// Returns the Drift [localId] of the upserted row, or `null` if the
  /// upsert was skipped (e.g. no serverId).
  ///
  /// Note: [teacherServerId] and [schoolServerId] are text columns with no
  /// local FK constraint, so no foreign-key resolution is required.
  Future<int?> _upsertExamFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ?? merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint('[sync] _upsertExamFromSync skipped: no serverId in $merged');
      return null;
    }

    // Look up existing exam by serverId.
    final existing = await (db.select(db.exams)
          ..where((t) => t.serverId.equals(serverId)))
        .get();

    // Map snake_case remote fields to Drift column values.
    String? strVal(String key) => merged[key] as String?;
    bool boolVal(String key) => merged[key] == true || merged[key] == 'true';
    int? intVal(String key) => _readInt(merged, key);
    DateTime? dateVal(String key) {
      final raw = merged[key];
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final classLevel = strVal('class_level') ?? '';
    final topic = strVal('topic') ?? '';
    final difficulty = strVal('difficulty') ?? '';
    final curriculum = strVal('curriculum') ?? '';
    final content = strVal('content') ?? '';
    final schemeOfWorkId = strVal('scheme_of_work_id');
    final weekNumber = intVal('week_number');
    final isDeleted = boolVal('is_deleted');
    final lastModifiedBy = strVal('last_modified_by');
    final teacherServerId = strVal('teacher_id') ?? strVal('teacher_server_id');
    final schoolServerId = strVal('school_id') ?? strVal('school_server_id');
    final isUnlocked = boolVal('is_unlocked');
    final term = strVal('term');
    final createdAt = dateVal('created_at') ?? DateTime.now();
    final updatedAt = dateVal('updated_at') ?? DateTime.now();
    final updateCounter = intVal('update_counter') ?? 0;

    if (existing.isNotEmpty) {
      // Update existing exam record.
      final existingExam = existing.first;

      // ── Empty-remote guard (mirrors _upsertLessonFromSync) ───────────────
      final resolvedSubject = await _resolveSubjectNameFromSync(
        merged,
        existingSubject: existingExam.subject,
      );
      final resolvedClassLevel =
          (classLevel.isEmpty && existingExam.classLevel.isNotEmpty)
              ? existingExam.classLevel
              : classLevel;
      final resolvedTopic = (topic.isEmpty && existingExam.topic.isNotEmpty)
          ? existingExam.topic
          : topic;

      await (db.update(db.exams)..where((t) => t.id.equals(existingExam.id)))
          .write(ExamsCompanion(
        serverId: Value(serverId),
        subject: Value(resolvedSubject),
        classLevel: Value(resolvedClassLevel),
        topic: Value(resolvedTopic),
        difficulty: Value(difficulty),
        curriculum: Value(curriculum),
        content: Value(content),
        schemeOfWorkId: schemeOfWorkId != null
            ? Value(schemeOfWorkId)
            : const Value.absent(),
        weekNumber:
            weekNumber != null ? Value(weekNumber) : const Value.absent(),
        isDeleted: Value(isDeleted),
        lastModifiedBy: lastModifiedBy != null
            ? Value(lastModifiedBy)
            : const Value.absent(),
        teacherServerId: teacherServerId != null
            ? Value(teacherServerId)
            : const Value.absent(),
        schoolServerId: schoolServerId != null
            ? Value(schoolServerId)
            : const Value.absent(),
        isUnlocked: Value(isUnlocked),
        term: term != null ? Value(term) : const Value.absent(),
        updatedAt: Value(updatedAt),
        updateCounter: Value(updateCounter),
      ));
      debugPrint('[sync] _upsertExamFromSync: UPDATED exam $serverId');
      return existingExam.id;
    } else {
      // Insert new exam record.
      final resolvedSubject = await _resolveSubjectNameFromSync(merged);
      final newLocalId = await (db.into(db.exams).insert(
            ExamsCompanion.insert(
              serverId: Value(serverId),
              subject: resolvedSubject,
              classLevel: classLevel,
              topic: topic,
              difficulty: difficulty,
              curriculum: curriculum,
              content: content,
              schemeOfWorkId: schemeOfWorkId != null
                  ? Value(schemeOfWorkId)
                  : const Value.absent(),
              weekNumber:
                  weekNumber != null ? Value(weekNumber) : const Value.absent(),
              isDeleted: Value(isDeleted),
              lastModifiedBy: lastModifiedBy != null
                  ? Value(lastModifiedBy)
                  : const Value.absent(),
              teacherServerId: teacherServerId != null
                  ? Value(teacherServerId)
                  : const Value.absent(),
              schoolServerId: schoolServerId != null
                  ? Value(schoolServerId)
                  : const Value.absent(),
              isUnlocked: Value(isUnlocked),
              term: term != null ? Value(term) : const Value.absent(),
              createdAt: Value(createdAt),
              updatedAt: Value(updatedAt),
            ),
          ));
      debugPrint('[sync] _upsertExamFromSync: INSERTED exam $serverId');
      return newLocalId;
    }
  }

  Future<String> _resolveSubjectNameFromSync(
    Map<String, dynamic> merged, {
    String? existingSubject,
  }) async {
    final remoteSubject = (merged['subject'] as String?)?.trim() ?? '';
    if (remoteSubject.isNotEmpty) {
      return remoteSubject;
    }

    final subjectServerId = (merged['subject_id'] as String?)?.trim();
    if (subjectServerId != null && subjectServerId.isNotEmpty) {
      final subjectRow = await (db.select(db.subjects)
            ..where((t) => t.serverId.equals(subjectServerId)))
          .getSingleOrNull();
      final resolvedSubject = subjectRow?.name.trim() ?? '';
      if (resolvedSubject.isNotEmpty) {
        return resolvedSubject;
      }
    }

    if (existingSubject != null && existingSubject.trim().isNotEmpty) {
      return existingSubject.trim();
    }

    return '';
  }

  /// Upserts a subject row from synced remote data into the local Drift
  /// [subjects] table. The [merged] map uses snake_case keys from Supabase.
  ///
  /// Returns the Drift [localId] of the upserted row, or `null` if the
  /// upsert was skipped (e.g. no serverId).
  Future<int?> _upsertSubjectFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ?? merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint(
          '[sync] _upsertSubjectFromSync skipped: no serverId in $merged');
      return null;
    }

    // Look up existing subject by serverId.
    final existing = await (db.select(db.subjects)
          ..where((t) => t.serverId.equals(serverId)))
        .get();

    // Map snake_case remote fields to Drift column values.
    String? strVal(String key) => merged[key] as String?;
    int? intVal(String key) => _readInt(merged, key);
    DateTime? dateVal(String key) {
      final raw = merged[key];
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final name = strVal('subject_name') ?? strVal('name') ?? '';
    final alias = strVal('alias');
    final schoolId = strVal('school_id');
    final sortOrder = intVal('sort_order') ?? 0;
    final createdAt = dateVal('created_at') ?? DateTime.now();
    final updatedAt = dateVal('updated_at') ?? DateTime.now();

    if (existing.isNotEmpty) {
      // Update existing subject record.
      final existingSubject = existing.first;
      await (db.update(db.subjects)
            ..where((t) => t.id.equals(existingSubject.id)))
          .write(SubjectsCompanion(
        serverId: Value(serverId),
        name: Value(name),
        alias: alias != null ? Value(alias) : const Value.absent(),
        schoolId: schoolId != null ? Value(schoolId) : const Value.absent(),
        sortOrder: Value(sortOrder),
        updatedAt: Value(updatedAt),
      ));
      debugPrint('[sync] _upsertSubjectFromSync: UPDATED subject $serverId');
      return existingSubject.id;
    } else {
      // Fallback: check for existing local row matching (schoolId, name)
      // before inserting, to avoid duplicates when the serverId hasn't
      // been synced yet but a local row already exists.
      if (schoolId != null && name.isNotEmpty) {
        final localMatch = await (db.select(db.subjects)
              ..where((t) => t.schoolId.equals(schoolId) & t.name.equals(name)))
            .get();
        if (localMatch.isNotEmpty) {
          final match = localMatch.first;
          // Update the matched row with the serverId and any new fields.
          await (db.update(db.subjects)..where((t) => t.id.equals(match.id)))
              .write(SubjectsCompanion(
            serverId: Value(serverId),
            name: Value(name),
            alias: alias != null ? Value(alias) : const Value.absent(),
            schoolId: schoolId != null ? Value(schoolId) : const Value.absent(),
            sortOrder: Value(sortOrder),
            updatedAt: Value(updatedAt),
          ));
          debugPrint(
              '[sync] _upsertSubjectFromSync: UPDATED local match ($schoolId, $name) with serverId $serverId');
          return match.id;
        }
      }
      // Insert new subject record.
      final newLocalId = await (db.into(db.subjects).insert(
            SubjectsCompanion.insert(
              serverId: Value(serverId),
              name: name,
              alias: alias != null ? Value(alias) : const Value.absent(),
              schoolId:
                  schoolId != null ? Value(schoolId) : const Value.absent(),
              sortOrder: Value(sortOrder),
              createdAt: Value(createdAt),
              updatedAt: Value(updatedAt),
            ),
          ));
      debugPrint('[sync] _upsertSubjectFromSync: INSERTED subject $serverId');
      return newLocalId;
    }
  }

  /// Upserts a scheme_of_work row from synced remote data into the local
  /// Drift [schemeOfWork] table. The [merged] map uses snake_case keys from
  /// Supabase.
  ///
  /// Unlike lessons/exams/subjects which have simple text serverId columns
  /// for their FKs, scheme_of_work has local integer FK columns
  /// (schoolId, teacherId, subjectId) that reference the local integer PKs
  /// of the schools, teachers, and subjects tables respectively. The remote
  /// payload contains server UUIDs for these references, so each must be
  /// resolved to its local integer ID via a serverId lookup.
  ///
  /// Returns the Drift [id] of the upserted row, or `null` if the upsert
  /// was skipped (e.g. no serverId, or a required FK could not be resolved).
  Future<int?> _upsertSchemeOfWorkFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ?? merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint(
        '[sync] _upsertSchemeOfWorkFromSync skipped: no serverId in $merged',
      );
      return null;
    }

    // Look up existing scheme_of_work by serverId.
    final existing = await (db.select(db.schemeOfWork)
          ..where((t) => t.serverId.equals(serverId)))
        .get();

    // ── Resolve local integer FKs from server UUIDs ────────────────
    // The remote payload contains UUID strings for school_id, teacher_id,
    // and subject_id. We must look up the corresponding local integer PKs.

    final schoolServerId = merged['school_id'] as String?;
    int? resolvedSchoolId;
    if (schoolServerId != null && schoolServerId.isNotEmpty) {
      final schoolRows = await (db.select(db.schools)
            ..where((s) => s.serverId.equals(schoolServerId)))
          .get();
      if (schoolRows.isNotEmpty) {
        resolvedSchoolId = schoolRows.first.localId;
      }
    }
    if (resolvedSchoolId == null) {
      debugPrint(
        '[sync] _upsertSchemeOfWorkFromSync: cannot resolve school_id '
        '($schoolServerId) — skipping scheme_of_work $serverId',
      );
      return null;
    }

    final teacherServerId = merged['teacher_id'] as String?;
    int? resolvedTeacherId;
    if (teacherServerId != null && teacherServerId.isNotEmpty) {
      final teacherRows = await (db.select(db.teachers)
            ..where((t) => t.serverId.equals(teacherServerId)))
          .get();
      if (teacherRows.isNotEmpty) {
        resolvedTeacherId = teacherRows.first.localId;
      }
    }
    if (resolvedTeacherId == null) {
      debugPrint(
        '[sync] _upsertSchemeOfWorkFromSync: cannot resolve teacher_id '
        '($teacherServerId) — skipping scheme_of_work $serverId',
      );
      return null;
    }

    final subjectServerId = merged['subject_id'] as String?;
    int? resolvedSubjectId;
    if (subjectServerId != null && subjectServerId.isNotEmpty) {
      final subjectRows = await (db.select(db.subjects)
            ..where((s) => s.serverId.equals(subjectServerId)))
          .get();
      if (subjectRows.isNotEmpty) {
        resolvedSubjectId = subjectRows.first.id;
      }
    }
    if (resolvedSubjectId == null) {
      debugPrint(
        '[sync] _upsertSchemeOfWorkFromSync: cannot resolve subject_id '
        '($subjectServerId) — skipping scheme_of_work $serverId',
      );
      return null;
    }

    // ── Map snake_case remote fields to Drift column values ────────
    String? strVal(String key) => merged[key] as String?;
    bool boolVal(String key) => merged[key] == true || merged[key] == 'true';
    int? intVal(String key) => _readInt(merged, key);
    DateTime? dateVal(String key) {
      final raw = merged[key];
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final term = strVal('term') ?? '';
    final weekNumber = intVal('week_number') ?? 1;
    final topic = strVal('topic') ?? '';
    final objectives = strVal('objectives') ?? '';
    final status = strVal('status') ?? 'draft';
    final adminEditedTopic = strVal('admin_edited_topic');
    final adminComment = strVal('admin_comment');
    final updateCounter = intVal('update_counter') ?? 0;
    final isDeleted = boolVal('is_deleted');
    final classLevel = strVal('class_level') ?? '';
    final createdAt = dateVal('created_at') ?? DateTime.now();
    final updatedAt = dateVal('updated_at') ?? DateTime.now();

    if (existing.isNotEmpty) {
      // Update existing scheme_of_work record.
      final existingRow = existing.first;
      await (db.update(db.schemeOfWork)
            ..where((t) => t.id.equals(existingRow.id)))
          .write(SchemeOfWorkCompanion(
        serverId: Value(serverId),
        schoolId: Value(resolvedSchoolId),
        teacherId: Value(resolvedTeacherId),
        subjectId: Value(resolvedSubjectId),
        term: Value(normalizeSowTermForServer(term)),
        weekNumber: Value(weekNumber),
        topic: Value(topic),
        objectives: Value(objectives),
        status: Value(status),
        adminEditedTopic: adminEditedTopic != null
            ? Value(adminEditedTopic)
            : const Value.absent(),
        adminComment:
            adminComment != null ? Value(adminComment) : const Value.absent(),
        updateCounter: Value(updateCounter),
        isDeleted: Value(isDeleted),
        classLevel: Value(classLevel),
        updatedAt: Value(updatedAt),
      ));
      debugPrint(
        '[sync] _upsertSchemeOfWorkFromSync: UPDATED scheme_of_work $serverId',
      );
      return existingRow.id;
    } else {
      // Insert new scheme_of_work record.
      final newLocalId = await (db.into(db.schemeOfWork).insert(
            SchemeOfWorkCompanion.insert(
              serverId: Value(serverId),
              schoolId: Value(resolvedSchoolId),
              teacherId: Value(resolvedTeacherId),
              subjectId: Value(resolvedSubjectId),
              term: Value(normalizeSowTermForServer(term)),
              weekNumber: Value(weekNumber),
              topic: Value(topic),
              objectives: Value(objectives),
              status: Value(status),
              adminEditedTopic: adminEditedTopic != null
                  ? Value(adminEditedTopic)
                  : const Value.absent(),
              adminComment: adminComment != null
                  ? Value(adminComment)
                  : const Value.absent(),
              updateCounter: Value(updateCounter),
              isDeleted: Value(isDeleted),
              classLevel: Value(classLevel),
              createdAt: Value(createdAt),
              updatedAt: Value(updatedAt),
            ),
          ));
      debugPrint(
        '[sync] _upsertSchemeOfWorkFromSync: INSERTED scheme_of_work $serverId',
      );
      return newLocalId;
    }
  }

  /// Removes duplicate teacher rows that share the same non-null [serverId],
  /// keeping only the row with the lowest [localId] for each serverId.
  ///
  /// Previous buggy sync runs (before school_id filtering was added) could
  /// insert the same teacher multiple times because there was no unique
  /// constraint on the server_id column. This method cleans up any such
  /// duplicates in a single pass using raw SQL.
  Future<void> _deduplicateTeachers() async {
    // Use raw SQL to find duplicate serverIds
    final dupRows = await db
        .customSelect(
          'SELECT server_id, COUNT(*) AS cnt '
          'FROM teachers '
          'WHERE server_id IS NOT NULL '
          'GROUP BY server_id '
          'HAVING COUNT(*) > 1',
        )
        .get();

    if (dupRows.isEmpty) return;

    int totalDeleted = 0;
    for (final row in dupRows) {
      final serverId = row.data['server_id'] as String;

      // Get all localIds for this serverId, ordered ascending
      final idRows = await db.customSelect(
        'SELECT local_id FROM teachers '
        'WHERE server_id = ? '
        'ORDER BY local_id ASC',
        variables: [Variable(serverId)],
      ).get();

      if (idRows.length <= 1) continue;

      final ids = idRows.map((r) => r.data['local_id'] as int).toList();
      final keepLocalId = ids.first;
      final deleteIds = ids.skip(1).toList();

      // Delete duplicate rows (keep lowest localId)
      await db.customStatement(
        'DELETE FROM teachers WHERE local_id IN (${deleteIds.join(',')})',
      );

      totalDeleted += deleteIds.length;
      debugPrint(
        '[sync] _deduplicateTeachers: kept localId=$keepLocalId, '
        'deleted ${deleteIds.length} duplicate(s) for serverId=$serverId',
      );
    }
    debugPrint(
      '[sync] _deduplicateTeachers: deleted $totalDeleted duplicate row(s) total',
    );
  }

  Future<String?> _loadBaseHash(String tableName, int localId) async {
    final rows = await (db.select(db.versionHashes)
          ..where((t) =>
              t.table.equals(tableName) & t.recordLocalId.equals(localId))
          ..orderBy([
            (t) => OrderingTerm(expression: t.setAt, mode: OrderingMode.desc),
          ]))
        .get();
    final row = rows.isEmpty ? null : rows.first;
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
      case 'teachers':
        return 1;
      case 'subjects':
        return 2;
      case 'lessons':
        return 3;
      case 'exams':
        return 4;
      case 'progress_logs':
        return 5;
      case 'scheme_of_work':
        return 6;
      case 'vault_items':
        return 7;
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

  /// Upserts a payment_events row from synced remote data into the local
  /// Drift [paymentEvents] table. The [merged] map uses snake_case keys from
  /// Supabase.
  ///
  /// Unlike tables with a serverId column, payment_events uses
  /// transactionReference as the unique lookup key — the remote payload has
  /// no server_id, and the local PK (auto-increment id) differs from the
  /// server PK (BIGSERIAL).
  ///
  /// Returns the Drift [id] of the upserted row, or `null` if the upsert
  /// was skipped (e.g. no transactionReference).
  Future<int?> _upsertPaymentEventFromSync(Map<String, dynamic> merged) async {
    final transactionReference = merged['transaction_reference'] as String?;
    if (transactionReference == null || transactionReference.isEmpty) {
      debugPrint(
        '[sync] _upsertPaymentEventFromSync skipped: '
        'no transactionReference in $merged',
      );
      return null;
    }

    // Look up existing payment_event by transactionReference.
    final existing = await (db.select(db.paymentEvents)
          ..where((t) => t.transactionReference.equals(transactionReference)))
        .get();

    // Map snake_case remote fields to Drift column values.
    String? strVal(String key) => merged[key] as String?;
    bool boolVal(String key) => merged[key] == true || merged[key] == 'true';
    int? intVal(String key) => _readInt(merged, key);
    DateTime? dateVal(String key) {
      final raw = merged[key];
      if (raw == null) return null;
      if (raw is DateTime) return raw;
      if (raw is String) return DateTime.tryParse(raw);
      return null;
    }

    final confirmedByWebhook = boolVal('confirmed_by_webhook');
    final amount = intVal('amount') ?? 0;
    final plan = strVal('plan') ?? '';
    final createdAt = dateVal('created_at') ?? DateTime.now();
    final confirmationDate = dateVal('confirmation_date');

    if (existing.isNotEmpty) {
      // Update existing payment_event record.
      final existingEvent = existing.first;
      await (db.update(db.paymentEvents)
            ..where((t) => t.id.equals(existingEvent.id)))
          .write(PaymentEventsCompanion(
        transactionReference: Value(transactionReference),
        confirmedByWebhook: Value(confirmedByWebhook),
        amount: Value(amount),
        plan: Value(plan),
        createdAt: Value(createdAt),
        confirmationDate: confirmationDate != null
            ? Value(confirmationDate)
            : const Value.absent(),
      ));
      debugPrint(
        '[sync] _upsertPaymentEventFromSync: UPDATED '
        'payment_event $transactionReference',
      );
      return existingEvent.id;
    } else {
      // Insert new payment_event in a single atomic SQL write.
      final newLocalId = await (db.into(db.paymentEvents).insert(
            PaymentEventsCompanion.insert(
              transactionReference: transactionReference,
              confirmedByWebhook: Value(confirmedByWebhook),
              amount: amount,
              plan: plan,
              createdAt: Value(createdAt),
              confirmationDate: confirmationDate != null
                  ? Value(confirmationDate)
                  : const Value.absent(),
            ),
          ));
      debugPrint(
        '[sync] _upsertPaymentEventFromSync: INSERTED '
        'payment_event $transactionReference',
      );
      return newLocalId;
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

/// Top-level helper: returns the serverId of a local record if it exists
/// and has one. Used by SyncService._pushChanges() to detect stale INSERT
/// queue entries where the previous push succeeded (row created, UUID returned
/// from server) but the cleanup was interrupted by a crash.
Future<String?> _getServerIdForQueueEntry(
  AppDatabase db,
  SyncQueueData entry,
) async {
  switch (entry.queueTable) {
    case 'lessons':
      final row = await (db.select(db.lessons)
            ..where((t) => t.id.equals(entry.recordLocalId)))
          .getSingleOrNull();
      return row?.serverId;
    case 'exams':
      final row = await (db.select(db.exams)
            ..where((t) => t.id.equals(entry.recordLocalId)))
          .getSingleOrNull();
      return row?.serverId;
    case 'scheme_of_work':
      final row = await (db.select(db.schemeOfWork)
            ..where((t) => t.id.equals(entry.recordLocalId)))
          .getSingleOrNull();
      return row?.serverId;
    case 'subjects':
      final row = await (db.select(db.subjects)
            ..where((t) => t.id.equals(entry.recordLocalId)))
          .getSingleOrNull();
      return row?.serverId;
    case 'vault_items':
      final row = await (db.select(db.vaultItems)
            ..where((t) => t.id.equals(entry.recordLocalId)))
          .getSingleOrNull();
      return row?.serverId;
    case 'progress_logs':
      final row = await (db.select(db.progressLogs)
            ..where((t) => t.id.equals(entry.recordLocalId)))
          .getSingleOrNull();
      return row?.serverId;
    default:
      return null;
  }
}
