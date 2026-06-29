import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/security_config.dart';
import 'package:classai/core/services/config_service.dart';

part 'security_config_dao.g.dart';

@DriftAccessor(tables: [SecurityConfig])
class SecurityConfigDao extends DatabaseAccessor<AppDatabase>
    with _$SecurityConfigDaoMixin {
  SecurityConfigDao(AppDatabase db) : super(db);

  Future<SecurityConfigData> get() {
    return (select(securityConfig)
          ..where((t) => t.id.equals(1))
          ..orderBy([(t) => OrderingTerm(expression: t.id)])
          ..limit(1))
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
    int? dailyPreviewCount,
    String? dailyPreviewDate,
  }) async {
    final config = await get();
    await (update(securityConfig)..where((t) => t.id.equals(config.id))).write(
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
        syncCursor:
            syncCursor != null ? Value(syncCursor) : const Value.absent(),
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
        lastSeenTime:
            lastSeenTime != null ? Value(lastSeenTime) : const Value.absent(),
        lastKnownGoodTime: lastKnownGoodTime != null
            ? Value(lastKnownGoodTime)
            : const Value.absent(),
        monotonicLastSeen: monotonicLastSeen != null
            ? Value(monotonicLastSeen)
            : const Value.absent(),
        dailyPreviewCount: dailyPreviewCount != null
            ? Value(dailyPreviewCount)
            : const Value.absent(),
        dailyPreviewDate: dailyPreviewDate != null
            ? Value(dailyPreviewDate)
            : const Value.absent(),
      ),
    );
  }

  Future<void> updateOfflineCredits(int newValue) async {
    await updateConfig(offlineCredits: newValue);
  }

  Future<void> clearCreditSpentBatchId() async {
    final config = await get();
    await (update(securityConfig)..where((t) => t.id.equals(config.id))).write(
      SecurityConfigCompanion(
        creditSpentBatchId: Value(null),
      ),
    );
  }

  // -----------------------------------------------------------------------
  /// Optional [ConfigService] injection for reading limits from remote config.
  ConfigService? _config;

  void setConfigService(ConfigService config) {
    _config = config;
  }

  /// Reads the daily preview limit for [tier] from remote config, falling
  /// back to the hardcoded defaults.
  int _previewLimit(String tier) {
    final limits = _config?.dailyPreviewLimits;
    if (limits != null && limits[tier] is int) {
      return limits[tier] as int;
    }
    const defaults = {'free': 0, 'basic': 10, 'standard': 10, 'elite': -1};
    return defaults[tier] ?? 10;
  }

  /// Reads the daily PDF export limit for [tier] from remote config, falling
  /// back to the hardcoded defaults.
  int _pdfLimit(String tier) {
    final limits = _config?.pdfExportLimits;
    if (limits != null && limits[tier] is int) {
      return limits[tier] as int;
    }
    const defaults = {'free': 1, 'basic': 3, 'standard': 5, 'elite': -1};
    return defaults[tier] ?? 1;
  }

  // Daily counter methods for rate limiting
  // -----------------------------------------------------------------------

  /// Check and increment the daily generation counter.
  /// Returns true if the generation is allowed, false if limit exceeded.
  /// Also resets the counter if the date has changed.
  Future<bool> checkAndIncrementDailyGenerations({required String tier}) async {
    final config = await get();
    final today = DateTime.now().toIso8601String().split('T').first;
    final currentCount = config.dailyGenerations;
    final currentDate = config.dailyGenerationDate;

    // Reset counter if date changed
    int newCount = currentCount;
    String newDate = currentDate ?? '';

    if (currentDate != today) {
      newCount = 0;
      newDate = today;
    }

    // Check limit based on tier
    final limit = _previewLimit(tier);

    if (limit > 0 && newCount >= limit) {
      return false; // Limit exceeded
    }

    // Increment and save
    await (update(securityConfig)..where((t) => t.id.equals(config.id))).write(
      SecurityConfigCompanion(
        dailyGenerations: Value(newCount + 1),
        dailyGenerationDate: Value(newDate),
      ),
    );

    return true;
  }

  /// Check and increment the daily preview counter.
  /// Returns true if the preview is allowed, false if limit exceeded.
  /// Also resets the counter if the date has changed.
  /// Elite tier has unlimited previews.
  Future<bool> checkAndIncrementDailyPreviews({required String tier}) async {
    final config = await get();
    final today = DateTime.now().toIso8601String().split('T').first;
    final currentCount = config.dailyPreviewCount;
    final currentDate = config.dailyPreviewDate;

    // Reset counter if date changed
    int newCount = currentCount;
    String newDate = currentDate ?? '';

    if (currentDate != today) {
      newCount = 0;
      newDate = today;
    }

    // Check limit based on tier
    final limit = _previewLimit(tier);

    if (limit > 0 && newCount >= limit) {
      return false; // Limit exceeded
    }

    // Increment and save
    await (update(securityConfig)..where((t) => t.id.equals(config.id))).write(
      SecurityConfigCompanion(
        dailyPreviewCount: Value(newCount + 1),
        dailyPreviewDate: Value(newDate),
      ),
    );

    return true;
  }

  /// Check and increment the daily PDF export counter.
  /// Returns true if the export is allowed, false if limit exceeded.
  /// Also resets the counter if the date has changed.
  Future<bool> checkAndIncrementDailyPdfExports({required String tier}) async {
    final config = await get();
    final today = DateTime.now().toIso8601String().split('T').first;
    final currentCount = config.dailyPdfExports;
    final currentDate = config.dailyPdfExportDate;

    // Reset counter if date changed
    int newCount = currentCount;
    String newDate = currentDate ?? '';

    if (currentDate != today) {
      newCount = 0;
      newDate = today;
    }

    // Check limit based on tier
    final limit = _pdfLimit(tier);

    if (limit > 0 && newCount >= limit) {
      return false; // Limit exceeded
    }

    // Increment and save
    await (update(securityConfig)..where((t) => t.id.equals(config.id))).write(
      SecurityConfigCompanion(
        dailyPdfExports: Value(newCount + 1),
        dailyPdfExportDate: Value(newDate),
      ),
    );

    return true;
  }

  /// Get remaining PDF exports for today.
  Future<int> getRemainingPdfExports({required String tier}) async {
    final config = await get();
    final today = DateTime.now().toIso8601String().split('T').first;

    // Reset counter if date changed
    if (config.dailyPdfExportDate != today) {
      return _getTierPdfLimit(tier);
    }

    final limit = _pdfLimit(tier);

    if (limit < 0) return -1; // Unlimited

    return limit - config.dailyPdfExports;
  }

  int _getTierPdfLimit(String tier) {
    return _pdfLimit(tier);
  }
}
