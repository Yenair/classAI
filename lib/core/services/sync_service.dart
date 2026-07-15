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

  const SyncPullPage({
    required this.changes,
    required this.nextCursor,
    this.activeTeacherIds,
    this.pendingTeachers,
  });

  factory SyncPullPage.fromJson(Map<String, dynamic> json) {
    final rawChanges = (json['changes'] as List? ?? const []);
    final rawPendingTeachers =
        (json['pending_teachers'] as List? ?? const []);
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
    'audit_logs',
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
        },
      );
      final data = response.data as Map<String, dynamic>?;
      if (data != null) {
        return SyncPullPage.fromJson(data);
      }
    } on FunctionException catch (e) {
      if (e.status == 401) {
        final code = (e.details is Map)
            ? (e.details as Map)['code'] as String?
            : null;
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
        final code = (e.details is Map)
            ? (e.details as Map)['code'] as String?
            : null;
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
      final response =
          await client.functions.invoke('sync-realtime-events',
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
        final code = (e.details is Map)
            ? (e.details as Map)['code'] as String?
            : null;
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
    required String resolution,
    required bool notified,
  });

  Future<List<SyncQueueData>> loadPendingQueue();

  Future<void> markQueueAttempt(int queueId, {DateTime? attemptedAt});

  Future<void> markQueueTerminalFailure(
    int queueId, {
    String? lastError,
    DateTime? failedAt,
  });

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
  }) {
    return db.securityConfigDao.updateConfig(
      lastPullTimestamp: lastPullTimestamp,
      syncCursor: syncCursor,
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
      final teacherChanges = page.changes
          .where((c) => c.table == 'teachers')
          .toList();
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

      for (final change in page.changes) {
        await _mergeRemoteChange(change);
      }

      // Capture metadata from each page (returned by the edge function
      // alongside the incremental changes).
      if (page.activeTeacherIds != null) {
        activeTeacherIds = page.activeTeacherIds;
      }
      if (page.pendingTeachers != null &&
          page.pendingTeachers!.isNotEmpty) {
        pendingTeachers = page.pendingTeachers;
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
      await _reconcileTeacherRoster(activeTeacherIds);
    }

    // Issue 3: Upsert any pending (force_password_reset=true) teachers that
    // may have been missed by the incremental pull because their record was
    // last modified before the sync cursor.
    if (pendingTeachers != null) {
      for (final change in pendingTeachers) {
        await _upsertTeacherFromSync(change.row);
      }
    }

    _setState(SyncState.pushing);
    await _pushChanges();
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

      final school = await db.schoolsDao.get();
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
  Future<void> _reconcileTeacherRoster(Set<String> activeServerIds) async {
    final localTeachers = await (db.select(db.teachers)
          ..where((t) => t.schoolServerId.equals(schoolId)))
        .get();

    for (final teacher in localTeachers) {
      if (teacher.forcePasswordReset) continue;
      if (teacher.serverId != null &&
          !activeServerIds.contains(teacher.serverId)) {
        await (db.delete(db.teachers)
              ..where((t) => t.localId.equals(teacher.localId)))
            .go();
        debugPrint(
          '[sync] _reconcileTeacherRoster: DELETED teacher '
          '${teacher.serverId} (not in server roster)',
        );
      }
    }
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

    debugPrint('[PUSH-QUEUE] Pending sync entries: ${sorted.length}');

    for (final entry in sorted) {
      final payload = _decodePayload(entry.payload);
      debugPrint('[PUSH-QUEUE] Entry ${entry.id}: '
          'table=${entry.queueTable}, '
          'operation=${entry.operation}, '
          'localId=${entry.recordLocalId}, '
          'attempts=${entry.attempts}');
      // Inject local_id so the server can echo it back in the results
      // array, enabling the client to match responses to entries.
      payload['local_id'] = entry.recordLocalId;
      // DIAG: Log the payload BEFORE compression to verify local_id was injected
      debugPrint('[PUSH-DIAG] Pre-compress payload for entry ${entry.id} '
          '(table=${entry.queueTable}, op=${entry.operation}): '
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

      debugPrint('[PUSH-RESULT] Entry ID: ${entry.id}, '
          'Table: ${entry.queueTable}, Operation: ${entry.operation}, '
          'Attempts: ${entry.attempts}');

      if (result == null) {
        debugPrint('[PUSH-RESULT] No result returned from server for this entry');
        await store.markQueueAttempt(entry.id);
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

      debugPrint('[PUSH-RESULT] Entry ${entry.id} not successful — '
          'retryable=${result.retryable}, attempts=${entry.attempts}');
      await store.markQueueAttempt(entry.id);
      final nextAttempts = entry.attempts + 1;
      final failureMessage = result.errorMessage ??
          'Sync push failed for ${entry.queueTable} ${entry.operation}';

      if (!result.retryable) {
        // ── Non-retryable: server indicated this entry will NEVER succeed
        // (e.g. admin-table push from a non-admin user, or a non-syncable
        // table). Preserve it as terminal so the failure stays visible.
        debugPrint(
          '[PUSH-RESULT] Marking non-retryable queue entry terminal '
          '(id=${entry.id}, table=${entry.queueTable}, '
          'operation=${entry.operation})',
        );
        await store.markQueueTerminalFailure(
          entry.id,
          lastError: failureMessage,
        );
      } else if (nextAttempts >= 5) {
        // ── Stuck item cleanup ──────────────────────────────────
        // Retain exhausted retries as terminal rows so the failure remains
        // visible instead of disappearing silently.
        debugPrint(
          '[PUSH-RESULT] Marking stuck queue entry terminal '
          '(id=${entry.id}, table=${entry.queueTable}, '
          'operation=${entry.operation}, attempts=$nextAttempts)',
        );
        await store.markQueueTerminalFailure(
          entry.id,
          lastError: failureMessage,
        );
      } else {
        debugPrint('[PUSH-RESULT] Entry ${entry.id} is retryable '
            '(attempt $nextAttempts/5), entering backoff');
        _setState(SyncState.backoff);
      }
    }
  }

  /// Updates the [serverId] column on a local record after a successful push.
  Future<void> _updateLocalServerId({
    required String tableName,
    required int localId,
    required String serverId,
  }) async {
    switch (tableName) {
      case 'lessons':
        await (db.update(db.lessons)
              ..where((t) => t.id.equals(localId)))
            .write(LessonsCompanion(
              serverId: Value(serverId),
              updatedAt: Value(DateTime.now()),
            ));
        break;
      case 'exams':
        await (db.update(db.exams)
              ..where((t) => t.id.equals(localId)))
            .write(ExamsCompanion(
              serverId: Value(serverId),
              updatedAt: Value(DateTime.now()),
            ));
        break;
      case 'scheme_of_work':
        await (db.update(db.schemeOfWork)
              ..where((t) => t.id.equals(localId)))
            .write(SchemeOfWorkCompanion(
              serverId: Value(serverId),
              updatedAt: Value(DateTime.now()),
            ));
        break;
      case 'vault_items':
        await (db.update(db.vaultItems)
              ..where((t) => t.id.equals(localId)))
            .write(VaultItemsCompanion(
              serverId: Value(serverId),
              updatedAt: Value(DateTime.now()),
            ));
        break;
      case 'teachers':
        await (db.update(db.teachers)
              ..where((t) => t.localId.equals(localId)))
            .write(TeachersCompanion(
              serverId: Value(serverId),
              updatedAt: Value(DateTime.now()),
            ));
        break;
      case 'schools':
        await (db.update(db.schools)
              ..where((t) => t.localId.equals(localId)))
            .write(SchoolsCompanion(
              serverId: Value(serverId),
              updatedAt: Value(DateTime.now()),
            ));
        break;
      case 'progress_logs':
        await (db.update(db.progressLogs)
              ..where((t) => t.id.equals(localId)))
            .write(ProgressLogsCompanion(
              serverId: Value(serverId),
              updatedAt: Value(DateTime.now()),
            ));
        break;
      case 'subjects':
        await (db.update(db.subjects)
              ..where((t) => t.id.equals(localId)))
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
    // Decompress the pulled change if it was compressed for 2G/3G optimization.
    final decompressed = PayloadCompressor.decompress(change.row);
    final remote = _normalizeRecord(decompressed);
    final localId = _readInt(remote, 'localId') ??
        _readInt(remote, 'local_id') ??
        _readInt(remote, 'id') ??
        0;
    final local =
        await store.loadLocalRecord(change.table, localId) ?? const {};
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

    // For the teachers table, also upsert the merged data into the
    // actual Drift teachers table so the admin dashboard can query it
    // locally (e.g. getPendingTeachers, getBySchool).
    if (change.table == 'teachers') {
      await _upsertTeacherFromSync(result.merged);
    }

    // For the schools table, also upsert the merged data into the
    // actual Drift schools table so the admin dashboard and any other
    // screen reading the local school record (subscriptionTier, etc.)
    // reflect the latest values without requiring a re-login.
    if (change.table == 'schools') {
      await _upsertSchoolFromSync(result.merged);
    }

    _setState(SyncState.merging);
  }

  /// Upserts a teacher row from synced remote data into the local Drift
  /// [teachers] table. The [merged] map uses snake_case keys from Supabase.
  Future<void> _upsertTeacherFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ??
        merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint('[sync] _upsertTeacherFromSync skipped: no serverId in $merged');
      return;
    }

    // Look up existing teacher by serverId
    final existing = await (db.select(db.teachers)
          ..where((t) => t.serverId.equals(serverId)))
        .get();

    // Map snake_case remote fields to Drift column values
    String? strVal(String key) => merged[key] as String?;
    bool boolVal(String key) =>
        merged[key] == true || merged[key] == 'true';
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
    final schoolKeyWrapped = strVal('school_key_wrapped') ??
        strVal('school_master_key_wrapped');
    final salt = strVal('salt');
    final currentDeviceId = strVal('current_device_id');
    final isDeleted = boolVal('is_deleted');
    final createdAt = dateVal('created_at') ?? DateTime.now();
    final updatedAt = dateVal('updated_at') ?? DateTime.now();
    final lastModifiedBy = strVal('last_modified_by');

    // Resolve schoolLocalId from schoolServerId
    int? resolvedSchoolLocalId;
    if (schoolServerId != null) {
      final schoolRow = await (db.select(db.schools)
            ..where((s) => s.serverId.equals(schoolServerId)))
          .getSingleOrNull();
      resolvedSchoolLocalId = schoolRow?.localId;
    }
    if (resolvedSchoolLocalId == null || resolvedSchoolLocalId == 0) {
      final anySchool = await (db.select(db.schools)).getSingleOrNull();
      resolvedSchoolLocalId = anySchool?.localId;
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
        tempPassword: tempPassword != null
            ? Value(tempPassword)
            : const Value.absent(),
        isDeleted: Value(isDeleted),
        updatedAt: Value(updatedAt),
        lastModifiedBy: lastModifiedBy != null
            ? Value(lastModifiedBy)
            : const Value.absent(),
        updateCounter: Value(existingTeacher.updateCounter + 1),
      ));
      debugPrint('[sync] _upsertTeacherFromSync: UPDATED teacher $serverId');
    } else {
      // Insert new teacher record
      await (db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: Value(serverId),
          email: email,
          teacherName: teacherName,
          role: Value(role),
          schoolLocalId:
              resolvedSchoolLocalId ?? 0,
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
        ),
      ));
      debugPrint('[sync] _upsertTeacherFromSync: INSERTED teacher $serverId');
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
  Future<void> _upsertSchoolFromSync(Map<String, dynamic> merged) async {
    final serverId = merged['server_id'] as String? ??
        merged['id'] as String?;
    if (serverId == null || serverId.isEmpty) {
      debugPrint('[sync] _upsertSchoolFromSync skipped: no serverId in $merged');
      return;
    }

    // Map snake_case remote keys to the parameters expected by upsertByServerId.
    String? strVal(String key) => merged[key] as String?;

    final schoolName = strVal('school_name') ?? '';
    final shortCode = strVal('short_code') ?? '';
    final subscriptionTier = strVal('subscription_tier') ?? 'free';
    final activeCurriculum = strVal('active_curriculum') ?? 'nerdc';
    final activeCurriculumVersion = strVal('active_curriculum_version');
    final totalSeats = _readInt(merged, 'total_seats') ?? 5;
    final schoolMasterKeyWrapped = strVal('school_master_key_wrapped') ??
        strVal('school_key_wrapped');
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

    await db.schoolsDao.upsertByServerId(
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
    final dupRows = await db.customSelect(
      'SELECT server_id, COUNT(*) AS cnt '
      'FROM teachers '
      'WHERE server_id IS NOT NULL '
      'GROUP BY server_id '
      'HAVING COUNT(*) > 1',
    ).get();

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
