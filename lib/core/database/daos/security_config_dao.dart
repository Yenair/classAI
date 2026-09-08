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
        syncCursor: Value(syncCursor),
        lastSyncAttemptTime: lastSyncAttemptTime != null
            ? Value(lastSyncAttemptTime)
            : const Value.absent(),
        syncCooldownUntil: Value(syncCooldownUntil),
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

    // security_config is a per-device local table with no server-side
    // counterpart.  The data it holds (offline credits, daily preview
    // counters, deviceId, etc.) is never pushed to the server.
    // Inserting a sync-queue entry here would produce an UPDATE against
    // the `security_config` PostgREST endpoint, which returns 404
    // because the relation does not exist on the server — causing stuck
    // entries that retry forever.  Therefore, we skip sync entirely for
    // this table.
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

  /// Reads the daily AI generation limit for [tier] from remote config,
  /// falling back to the hardcoded defaults.
  int _generationLimit(String tier) {
    final limits = _config?.dailyGenerationLimits;
    if (limits != null && limits[tier] is int) {
      return limits[tier] as int;
    }
    const defaults = {'free': 0, 'basic': 5, 'standard': 10, 'elite': -1};
    return defaults[tier] ?? 5;
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

  /// Reads the unified daily credit limit for [tier] from remote config,
  /// falling back to the hardcoded defaults.
  int _dailyCreditLimit(String tier) {
    final limits = _config?.dailyCreditsLimit;
    if (limits != null && limits[tier] is int) {
      return limits[tier] as int;
    }
    const defaults = {'free': 3, 'basic': 1, 'standard': 3, 'elite': -1};
    return defaults[tier] ?? 1;
  }

  /// The tier's unified daily credit limit (remote-config value with the
  /// hardcoded fallback). Public so limit-reached messaging can include
  /// the limit, matching getDailyGenerationLimit().
  int getDailyCreditLimit(String tier) => _dailyCreditLimit(tier);

  // Unified daily credits (R2 unification)
  // -----------------------------------------------------------------------

  /// The local day (yyyy-MM-dd) right now, in the same format the
  /// daily_credits_date column stores.
  static String _today() =>
      DateTime.now().toIso8601String().split('T').first;

  /// Check and spend [cost] unified daily credits for [tier].
  ///
  /// Always spends — there is no read-only mode (2B.3 vs 2B.4 split:
  /// display widgets use [getRemainingDailyCredits], actions call this).
  ///
  /// Balance semantics: `offlineCredits` holds the REMAINING unified daily
  /// credits. On a new local day it resets to the tier limit. Elite (-1
  /// limit) is unlimited — always allowed, balance not tracked.
  ///
  /// Returns true if the spend is allowed (balance decremented), false if
  /// the balance can't cover the cost (nothing written).
  Future<bool> checkAndSpendDailyCredits({
    required String tier,
    int cost = 1,
  }) async {
    final config = await get();
    final today = _today();
    final limit = _dailyCreditLimit(tier);

    // Elite (-1) is unlimited: never block, never track a balance.
    if (limit < 0) return true;

    // Balance resets on a new local day. Server time corrections arrive via
    // sync (2C), overwriting dailyCreditsDate + balance together.
    final bool isNewDay = config.dailyCreditsDate != today;
    final int balance = isNewDay ? limit : config.offlineCredits;

    if (balance < cost) {
      // Exhausted — leave state untouched.
      return false;
    }

    await (update(securityConfig)..where((t) => t.id.equals(config.id))).write(
      SecurityConfigCompanion(
        offlineCredits: Value(balance - cost),
        dailyCreditsDate: Value(today),
      ),
    );
    return true;
  }

  /// Get remaining unified daily credits for today. Read-only — never
  /// writes, so calling it for display does not consume anything.
  ///
  /// Returns -1 for unlimited (elite), or the count remaining (>= 0).
  Future<int> getRemainingDailyCredits({required String tier}) async {
    final config = await get();
    final today = _today();
    final limit = _dailyCreditLimit(tier);

    if (limit < 0) return -1; // Unlimited

    if (config.dailyCreditsDate != today) {
      // New day: full quota available (no reset written — read-only).
      return limit;
    }

    return config.offlineCredits.clamp(0, limit);
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

    // Check limit based on tier — uses _generationLimit, NOT _previewLimit
    final limit = _generationLimit(tier);

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

  /// Get remaining daily generations for today.
  /// Returns -1 for unlimited (elite), or the count remaining (>= 0).
  Future<int> getRemainingDailyGenerations({required String tier}) async {
    final config = await get();
    final today = DateTime.now().toIso8601String().split('T').first;

    if (config.dailyGenerationDate != today) {
      return _getTierGenerationLimit(tier);
    }

    final limit = _generationLimit(tier);
    if (limit < 0) return -1; // Unlimited
    return (limit - config.dailyGenerations).clamp(0, limit);
  }

  /// The tier's daily generation limit (remote-config value with the
  /// hardcoded fallback). Public so limit-reached messaging can include
  /// the usage, e.g. "Daily generation limit reached (5/5 today)."
  int getDailyGenerationLimit(String tier) => _generationLimit(tier);

  int _getTierGenerationLimit(String tier) {
    return _generationLimit(tier);
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
