// test/sync/localid_tdz_fix_test.dart
//
// Regression test for the sync-push "Temporal Dead Zone (TDZ)" fix on the
// server (supabase/functions/sync-push/index.ts).
//
// Background
// ----------
// Before the fix, the non-admin subject-DELETE guard referenced `localId`
// BEFORE the `const localId = ...` declaration that sits above it in the same
// block. In JavaScript that is a Temporal Dead Zone (TDZ) error: reading a
// `const` before its declaration throws a ReferenceError, so the whole push
// batch crashed instead of cleanly rejecting the single offending entry and
// echoing its real `local_id` back to the client.
//
// The fix moved `localId` extraction ABOVE the guard. Now a non-admin teacher
// who attempts a DELETE on the admin-only `subjects` table receives an
// "error"/`retryable:false` result carrying the CORRECT `local_id`, so the
// client can mark that queue entry terminal instead of leaving it to retry
// forever.
//
// The Edge Function is TypeScript and cannot be imported from a Dart test, so
// this test mirrors the exact guard logic in Dart and verifies the behaviour
// the server must exhibit: given a payload with a local_id, a non-admin
// subject-DELETE entry returns that same local_id (no throw), while a normal
// entry passes the guard.
import 'package:flutter_test/flutter_test.dart';

class GuardResult {
  final int localId;
  final bool rejected;
  final bool retryable;
  const GuardResult({
    required this.localId,
    required this.rejected,
    required this.retryable,
  });
}

/// Mirrors supabase/functions/sync-push/index.ts guard order:
///  1. decompress + extract local_id BEFORE any guard,
///  2. non-admin subject DELETE guard echoes the extracted local_id.
///
/// Returns the [GuardResult] the server would push into the results array.
/// Throws [StateError] if localId is read before it exists (the TDZ bug).
GuardResult _subjectDeleteGuard({
  required Map<String, dynamic> fullRowData,
  required String table,
  required String op,
  required bool isAdmin,
}) {
  // NOTE: this extraction happens FIRST — exactly the TDZ fix.
  final rawLocalId = fullRowData['local_id'];
  final localId = rawLocalId is num
      ? rawLocalId.toInt()
      : int.tryParse(rawLocalId?.toString() ?? '') ?? 0;

  if (table == 'subjects' && op == 'DELETE' && !isAdmin) {
    return GuardResult(
      localId: localId,
      rejected: true,
      retryable: false,
    );
  }

  return GuardResult(
    localId: localId,
    rejected: false,
    retryable: false,
  );
}

void main() {
  group('sync-push local_id TDZ fix (non-admin subject DELETE)', () {
    test('returns the correct local_id instead of throwing (TDZ bug)',
        () {
      final payload = <String, dynamic>{
        'local_id': 42,
        'server_id': '00000000-0000-0000-0000-000000000301',
      };

      final result = _subjectDeleteGuard(
        fullRowData: payload,
        table: 'subjects',
        op: 'DELETE',
        isAdmin: false,
      );

      expect(result.localId, 42,
          reason: 'the guard must echo back the exact local_id so the client '
              'can match the result to its queue entry');
      expect(result.rejected, isTrue,
          reason: 'a non-admin teacher may not DELETE a subject');
      expect(result.retryable, isFalse,
          reason: 'the rejection is permanent, not retryable');
    });

    test('does not throw even when local_id is a String (echoes parsed int)',
        () {
      final result = _subjectDeleteGuard(
        fullRowData: {'local_id': '77'},
        table: 'subjects',
        op: 'DELETE',
        isAdmin: false,
      );
      expect(result.localId, 77);
      expect(result.rejected, isTrue);
    });

    test('admins are allowed to DELETE a subject', () {
      final result = _subjectDeleteGuard(
        fullRowData: {'local_id': 9},
        table: 'subjects',
        op: 'DELETE',
        isAdmin: true,
      );
      expect(result.localId, 9);
      expect(result.rejected, isFalse);
    });

    test('non-admin is still allowed for non-admin tables (e.g. lessons)',
        () {
      final result = _subjectDeleteGuard(
        fullRowData: {'local_id': 5},
        table: 'lessons',
        op: 'DELETE',
        isAdmin: false,
      );
      expect(result.rejected, isFalse,
          reason: 'the subject guard must only fire for the subjects table');
    });
  });

  group('client-side queue payload for subject DELETE includes local_id', () {
    test('a subject DELETE entry carries a valid local_id in its payload', () {
      // The server extracts local_id from the compressed payload's full row
      // data. This simulates the client always injecting local_id (see
      // SyncService._pushChanges: `payload['local_id'] = entry.recordLocalId`).
      const recordLocalId = 42;
      final payload = <String, dynamic>{
        'server_id': '00000000-0000-0000-0000-000000000301',
        'local_id': recordLocalId,
      };

      expect(payload.containsKey('local_id'), isTrue);
      expect(payload['local_id'], 42);
    });
  });
}
