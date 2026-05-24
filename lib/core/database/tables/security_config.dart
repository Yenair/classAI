import 'package:drift/drift.dart';

class SecurityConfig extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSeenTime =>
      dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastKnownGoodTime => dateTime().nullable()();
  RealColumn get monotonicLastSeen => real().nullable()();

  // Credit state
  IntColumn get offlineCredits => integer().withDefault(const Constant(3))();
  TextColumn get creditSpentIdsLocal =>
      text().withDefault(const Constant('[]'))(); // JSON array
  IntColumn get creditServerCounter =>
      integer().withDefault(const Constant(0))();
  TextColumn get creditSpentBatchId => text().nullable()();
  DateTimeColumn get lastCreditRefillServerTime => dateTime().nullable()();

  // Sync metadata
  DateTimeColumn get lastPullTimestamp => dateTime().nullable()();
  TextColumn get syncCursor => text().nullable()();
  DateTimeColumn get lastSyncAttemptTime => dateTime().nullable()();
  DateTimeColumn get syncCooldownUntil => dateTime().nullable()();
  IntColumn get lastRealtimeEventId =>
      integer().withDefault(const Constant(0))();

  // Security
  DateTimeColumn get heartbeatLastSuccess => dateTime().nullable()();
  DateTimeColumn get lastVacuumDate => dateTime().nullable()();
  TextColumn get encryptionKeyWrapped => text().nullable()();
  BoolColumn get encryptionRecoveryNeeded =>
      boolean().withDefault(const Constant(false))();
  TextColumn get corruptedRecordIds =>
      text().withDefault(const Constant('[]'))();
  IntColumn get lastKnownPasswordHashVersion =>
      integer().withDefault(const Constant(1))();

  // Session key for background sync
  TextColumn get sessionKeyEncrypted => text().nullable()();
  DateTimeColumn get sessionKeyExpiry => dateTime().nullable()();
  BoolColumn get syncPendingAfterBiometricTimeout =>
      boolean().withDefault(const Constant(false))();

  // Device identity
  TextColumn get currentDeviceId => text()();

  // Daily counters for rate limiting
  IntColumn get dailyGenerations => integer().withDefault(const Constant(0))();
  TextColumn get dailyGenerationDate => text().nullable()();
  IntColumn get dailyPdfExports => integer().withDefault(const Constant(0))();
  TextColumn get dailyPdfExportDate => text().nullable()();

  // VACUUM
  BoolColumn get pendingDbReplacement =>
      boolean().withDefault(const Constant(false))();
  TextColumn get vacuumedDbPath => text().nullable()();
}
