
```markdown
`phase_04_sync.md`
# Phase 4: Sync Engine (Self-Contained)

**Goal**: Complete offline-first sync with three-way merge, paginated pull, topological push, conflict detection, and emergency queue. Tested with simulated network conditions.

## State Machine: Sync

```
SyncState:
  idle → [connectivityRestored && !cooldownActive] → acquiringSession
  acquiringSession → [foreground && biometricAvailable] → biometricPrompt
  acquiringSession → [background && sessionKeyValid] → sessionKeyDecrypt
  acquiringSession → [background && !sessionKeyValid] → idle (abort, no biometric in background)
  biometricPrompt → [timeout] → idle (scheduleRetry5min)
  biometricPrompt → [success] → pulling
  biometricPrompt → [failure] → idle
  sessionKeyDecrypt → pulling

  pulling → [pageComplete] → merging
  merging → [conflictsFound] → savingConflicts → merging
  merging → [allMerged] → pushing
  pushing → [batchComplete] → applyingCredits
  pushing → [retryableError && attempts < 5] → backoff → pushing
  pushing → [fatalError] → idle (log error)

  applyingCredits → [deactivated] → emergencySave → forcedLogout
  applyingCredits → [active] → updatingMetadata → replayingRealtime → idle
```

## Architecture Decisions (This Phase Only)

- **Pull first, then merge, then push** (corrected from V8.2).
- **Three-way merge** using `version_hashes` table for base ancestor. If hash missing: treat as first-sync, save local version to conflicts table, apply remote.
- **Topological sort for push**: schools → subjects → lessons → exams → progress_logs. INSERT before UPDATE. But server must **accept unresolved FKs** and defer validation (nullable FK columns on server).
- **Realtime deduplication by server event ID**, NOT timestamp. Server issues monotonically increasing `event_id` per school.
- **Emergency queue**: Items with `is_emergency = true`. Pushed first on next login. If account still deactivated: queue preserved.
- **Conflict table**: `record_type`, `record_local_id`, `conflicting_fields` (JSON), `resolution` (enum), `notified`.

## Agent Playbook — Phase 4 File Creation Order

### Step 4.1: Sync Service Implementation

`lib/core/services/sync_service.dart` — full implementation of the state machine above.

Key methods:
```dart
class SyncService {
  Future<void> onConnectivityRestored();
  Future<void> _acquireSession();
  Future<void> _pullChanges();
  Future<MergeResult> _threeWayMerge(Record local, Record remote, String? baseHash);
  Future<void> _pushChanges(); // topologically sorted
  Future<void> _applyCreditState();
  Future<void> _replayRealtimeEvents(int lastEventId);
}
```

### Step 4.2: Merge Engine

`lib/core/services/merge_engine.dart`:

```dart
class MergeEngine {
  /// Three-way merge: local, remote, base (common ancestor)
  MergeResult merge({
    required Map<String, dynamic> local,
    required Map<String, dynamic> remote,
    required Map<String, dynamic>? base,
    required String tableName,
    required Map<String, MergeStrategy> fieldStrategies,
  }) {
    if (base == null) {
      // No common ancestor: save local to conflicts, apply remote
      return MergeResult(
        merged: remote,
        conflictingFields: local.keys.toList(),
        resolution: MergeResolution.remote,
      );
    }

    final merged = <String, dynamic>{};
    final conflicts = <String>[];

    // Iterate ALL fields — union of local and remote keys
    // (local-only iteration misses fields that exist in remote but not local)
    final allFields = {...local.keys, ...remote.keys};
    for (final field in allFields) {
      final localVal = local[field];
      final remoteVal = remote[field];
      final baseVal = base[field];

      // Detect changes: a field changed if its value differs from base
      // If baseVal is null (field not in base), it's a new field — treat as changed on whichever side has it
      final localChanged = localVal != baseVal;
      final remoteChanged = remoteVal != baseVal;

      if (!localChanged && !remoteChanged) {
        merged[field] = baseVal ?? localVal ?? remoteVal; // no changes; use any non-null value
      } else if (localChanged && !remoteChanged) {
        merged[field] = localVal; // local wins
      } else if (!localChanged && remoteChanged) {
        merged[field] = remoteVal; // remote wins
      } else {
        // Both changed: apply field strategy
        final strategy = fieldStrategies[field] ?? MergeStrategy.lwwByUpdateCounter;
        final result = _applyStrategy(
          localVal, remoteVal,
          local['updateCounter'] as int? ?? 0,
          remote['updateCounter'] as int? ?? 0,
          strategy,
        );
        merged[field] = result.value;
        if (result.isConflict) conflicts.add(field);
      }
    }

    return MergeResult(
      merged: merged,
      conflictingFields: conflicts,
      resolution: conflicts.isEmpty ? MergeResolution.merged : MergeResolution.unresolved,
    );
  }
}

enum MergeStrategy { lwwByUpdateCounter, union, keepLocal, keepRemote, manual }

class MergeResult {
  final Map<String, dynamic> merged;
  final List<String> conflictingFields;
  final MergeResolution resolution;
}

enum MergeResolution { local, remote, merged, unresolved }
```
```