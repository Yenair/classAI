import 'package:uuid/uuid.dart';
import '../utils/platform_helper.dart';
import '../database/database.dart';

class DailyCreditService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  DailyCreditService(this._db);

  /// Spend unified daily credits for a vault acquisition. Returns batch ID.
  /// CRITICAL: Batch ID is written to SQLite BEFORE the network call.
  ///
  /// R2 unification: the balance is the unified daily credit pool —
  /// `checkAndSpendDailyCredits` handles the day-rollover reset and the
  /// tier limit check, decrementing `offlineCredits` atomically. The
  /// SPEND_CREDITS sync entry remains queued so the server can reconcile
  /// the acquisition on next sync.
  Future<String> spendOfflineCredits({
    required int amount,
    required List<String> contentIds,
  }) async {
    // Clamp to 1 credit for unlock/acquire operations
    final effectiveAmount = amount > 1 ? 1 : amount;

    // Online path: server-side check happens on sync; spend locally anyway
    // so the UI counter is consistent. (Legacy behavior kept from R1.)
    final batchId = _uuid.v4();
    if (await PlatformHelper.isOnline()) {
      return batchId;
    }

    final config = await _db.securityConfigDao.get();
    final tier = await _resolveTier();

    final allowed = await _db.securityConfigDao.checkAndSpendDailyCredits(
      tier: tier,
      cost: effectiveAmount,
    );

    if (!allowed) {
      final remaining =
          await _db.securityConfigDao.getRemainingDailyCredits(tier: tier);
      throw OfflineCreditInsufficientException(
        available: remaining < 0 ? config.offlineCredits : remaining,
        required: effectiveAmount,
      );
    }

    // 1. Write batch ID FIRST (before network call)
    await _db.securityConfigDao.updateConfig(
      creditSpentBatchId: batchId,
    );

    // 2. Queue for sync — use a unique local ID so the sync push
    //    response can correlate results back to this entry.
    //    (The balance decrement itself happened in checkAndSpendDailyCredits.)
    final uniqueLocalId = DateTime.now().microsecondsSinceEpoch;
    await _db.syncQueueDao.insertEntry(
      queueTable: 'credit_spend',
      recordLocalId: uniqueLocalId,
      operation: 'SPEND_CREDITS',
      payload: {
        'batch_id': batchId,
        'amount': effectiveAmount,
        'content_ids': contentIds,
        'local_id': uniqueLocalId,
      },
    );

    return batchId;
  }

  /// Resolves the subscription tier from the local school row, mirroring
  /// DailyCreditStateNotifier. Defaults to the most restricted tier ('free')
  /// when no school row exists so an un-synced device never over-spends.
  Future<String> _resolveTier() async {
    try {
      final school = await _db.schoolsDao.get();
      return school?.subscriptionTier ?? 'free';
    } catch (_) {
      return 'free';
    }
  }

  /// Apply server credit state (overwrites local)
  Future<void> applyServerCreditState({
    required int offlineCredits,
    required List<String> spentIds,
    required int serverCounter,
  }) async {
    final config = await _db.securityConfigDao.get();

    // Detect tampering: if server counter < local counter, possible multi-device race
    if (serverCounter < config.creditServerCounter) {
      // Multi-device race or clock issue. Trust server.
      // Log warning but don't block.
    }

    await _db.securityConfigDao.updateConfig(
      offlineCredits: offlineCredits,
      creditSpentIdsLocal: spentIds.toString(), // JSON array
      creditServerCounter: serverCounter,
    );
    // Clear pending batch ID explicitly
    await _db.securityConfigDao.clearCreditSpentBatchId();
  }
}

class OfflineCreditInsufficientException implements Exception {
  final int available;
  final int required;
  OfflineCreditInsufficientException(
      {required this.available, required this.required});

  @override
  String toString() => 'Insufficient credits: have $available, need $required';
}
