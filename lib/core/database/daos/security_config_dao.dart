import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/security_config.dart';

part 'security_config_dao.g.dart';

@DriftAccessor(tables: [SecurityConfig])
class SecurityConfigDao extends DatabaseAccessor<AppDatabase>
    with _$SecurityConfigDaoMixin {
  SecurityConfigDao(AppDatabase db) : super(db);

  Future<SecurityConfigData> get() {
    return (select(securityConfig)..where((t) => t.id.equals(1)))
        .getSingle();
  }

  Future<void> updateConfig({
    int? offlineCredits,
    String? creditSpentBatchId,
    String? creditSpentIdsLocal,
    int? creditServerCounter,
    DateTime? lastCreditRefillServerTime,
    DateTime? lastPullTimestamp,
    String? syncCursor,
    DateTime? lastSyncAttemptTime,
    DateTime? syncCooldownUntil,
    int? lastRealtimeEventId,
    DateTime? heartbeatLastSuccess,
    DateTime? lastVacuumDate,
    String? encryptionKeyWrapped,
    bool? encryptionRecoveryNeeded,
    String? corruptedRecordIds,
    int? lastKnownPasswordHashVersion,
    String? sessionKeyEncrypted,
    DateTime? sessionKeyExpiry,
    bool? syncPendingAfterBiometricTimeout,
    String? currentDeviceId,
    bool? pendingDbReplacement,
    String? vacuumedDbPath,
    bool? isLocked,
    DateTime? lastSeenTime,
    DateTime? lastKnownGoodTime,
    double? monotonicLastSeen,
  }) async {
    final config = await get();
    await (update(securityConfig)..where((t) => t.id.equals(config.id)))
        .write(
      SecurityConfigCompanion(
        offlineCredits: offlineCredits != null
            ? Value(offlineCredits)
            : const Value.absent(),
        creditSpentBatchId: creditSpentBatchId != null
            ? Value(creditSpentBatchId)
            : const Value.absent(),
        creditSpentIdsLocal: creditSpentIdsLocal != null
            ? Value(creditSpentIdsLocal)
            : const Value.absent(),
        creditServerCounter: creditServerCounter != null
            ? Value(creditServerCounter)
            : const Value.absent(),
        lastCreditRefillServerTime: lastCreditRefillServerTime != null
            ? Value(lastCreditRefillServerTime)
            : const Value.absent(),
        lastPullTimestamp: lastPullTimestamp != null
            ? Value(lastPullTimestamp)
            : const Value.absent(),
        syncCursor: syncCursor != null
            ? Value(syncCursor)
            : const Value.absent(),
        lastSyncAttemptTime: lastSyncAttemptTime != null
            ? Value(lastSyncAttemptTime)
            : const Value.absent(),
        syncCooldownUntil: syncCooldownUntil != null
            ? Value(syncCooldownUntil)
            : const Value.absent(),
        lastRealtimeEventId: lastRealtimeEventId != null
            ? Value(lastRealtimeEventId)
            : const Value.absent(),
        heartbeatLastSuccess: heartbeatLastSuccess != null
            ? Value(heartbeatLastSuccess)
            : const Value.absent(),
        lastVacuumDate: lastVacuumDate != null
            ? Value(lastVacuumDate)
            : const Value.absent(),
        encryptionKeyWrapped: encryptionKeyWrapped != null
            ? Value(encryptionKeyWrapped)
            : const Value.absent(),
        encryptionRecoveryNeeded: encryptionRecoveryNeeded != null
            ? Value(encryptionRecoveryNeeded)
            : const Value.absent(),
        corruptedRecordIds: corruptedRecordIds != null
            ? Value(corruptedRecordIds)
            : const Value.absent(),
        lastKnownPasswordHashVersion: lastKnownPasswordHashVersion != null
            ? Value(lastKnownPasswordHashVersion)
            : const Value.absent(),
        sessionKeyEncrypted: sessionKeyEncrypted != null
            ? Value(sessionKeyEncrypted)
            : const Value.absent(),
        sessionKeyExpiry: sessionKeyExpiry != null
            ? Value(sessionKeyExpiry)
            : const Value.absent(),
        syncPendingAfterBiometricTimeout:
            syncPendingAfterBiometricTimeout != null
                ? Value(syncPendingAfterBiometricTimeout)
                : const Value.absent(),
        currentDeviceId: currentDeviceId != null
            ? Value(currentDeviceId)
            : const Value.absent(),
        pendingDbReplacement: pendingDbReplacement != null
            ? Value(pendingDbReplacement)
            : const Value.absent(),
        vacuumedDbPath: vacuumedDbPath != null
            ? Value(vacuumedDbPath)
            : const Value.absent(),
        isLocked: isLocked != null ? Value(isLocked) : const Value.absent(),
        lastSeenTime: lastSeenTime != null
            ? Value(lastSeenTime)
            : const Value.absent(),
        lastKnownGoodTime: lastKnownGoodTime != null
            ? Value(lastKnownGoodTime)
            : const Value.absent(),
        monotonicLastSeen: monotonicLastSeen != null
            ? Value(monotonicLastSeen)
            : const Value.absent(),
      ),
    );
  }

  Future<void> updateOfflineCredits(int newValue) async {
    await updateConfig(offlineCredits: newValue);
  }

  Future<void> clearCreditSpentBatchId() async {
    final config = await get();
    await (update(securityConfig)..where((t) => t.id.equals(config.id)))
        .write(
      SecurityConfigCompanion(
        creditSpentBatchId: Value(null),
      ),
    );
  }
}
