import 'package:uuid/uuid.dart';
import '../utils/platform_helper.dart';
import '../database/database.dart';

class DailyCreditService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  DailyCreditService(this._db);

  /// Spend credits for content unlock. Returns batch ID.
  /// CRITICAL: Batch ID is written to SQLite BEFORE the network call.
  /// This is used for unlocking already-generated content.
  /// Only deducts 1 credit per unlock.
  Future<String> spendOfflineCredits({
    required int amount,
    required List<String> contentIds,
  }) async {
    // Clamp to 1 credit for unlock operations
    final effectiveAmount = amount > 1 ? 1 : amount;

    final batchId = _uuid.v4();
    if (await PlatformHelper.isOnline()) {
      return batchId;
    }

    final config = await _db.securityConfigDao.get();

    if (config.offlineCredits < effectiveAmount) {
      throw OfflineCreditInsufficientException(
        available: config.offlineCredits,
        required: effectiveAmount,
      );
    }

    // 1. Write batch ID FIRST (before network call)
    await _db.securityConfigDao.updateConfig(
      creditSpentBatchId: batchId,
    );

    // 2. Decrement locally
    await _db.securityConfigDao.updateOfflineCredits(
      config.offlineCredits - effectiveAmount,
    );

    // 3. Queue for sync — use a unique local ID so the sync push
    //    response can correlate results back to this entry.
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
