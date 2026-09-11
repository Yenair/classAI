import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/credit_service.dart';
import 'package:classai/core/utils/platform_helper.dart';

void main() {
  late AppDatabase db;
  late DailyCreditService creditService;

  /// Today's date in the same format the DAO stores: yyyy-MM-dd.
  String today() => DateTime.now().toIso8601String().split('T').first;

  setUp(() async {
    // spendOfflineCredits short-circuits when the host reports online;
    // pin the connectivity seam so the local-spend path is exercised
    // deterministically on any machine.
    PlatformHelper.isOnlineOverride = false;
    db = AppDatabase.forTesting();
    await db.initialize();
    creditService = DailyCreditService(db);
    // Seed a today-stamped unified balance of 10 (no school row -> tier
    // resolves to 'free', limit 3; stamping today keeps the seeded balance
    // authoritative instead of resetting to the tier limit).
    await db.securityConfigDao.updateConfig(offlineCredits: 10);
    await db.securityConfigDao.updateConfig(dailyCreditsDate: today());
  });

  tearDown(() async {
    PlatformHelper.isOnlineOverride = null;
    await db.close();
  });

  test('spend credits decrements locally', () async {
    // spendOfflineCredits clamps amount>1 to 1 (only deducts 1 credit per unlock)
    final batchId = await creditService.spendOfflineCredits(
      amount: 2,
      contentIds: ['content_1'],
    );

    final config = await db.securityConfigDao.get();
    expect(config.offlineCredits, equals(9)); // 10 - 1 (clamped)
    expect(config.creditSpentBatchId, equals(batchId));
  });

  test('spend credits when insufficient throws', () async {
    // R2 unified pool: no school row -> tier resolves to 'free' (limit 3).
    // A today-stamped balance of 0 cannot cover the cost, so the spend is
    // rejected and the insufficient exception is thrown.
    await db.update(db.securityConfig).write(
          SecurityConfigCompanion(
            offlineCredits: const Value(0),
            dailyCreditsDate: Value(
              DateTime.now().toIso8601String().split('T').first,
            ),
          ),
        );
    await expectLater(
      () => creditService.spendOfflineCredits(amount: 20, contentIds: ['x']),
      throwsA(isA<OfflineCreditInsufficientException>()),
    );
  });

  test('batch ID is persisted before spend', () async {
    final batchId = await creditService.spendOfflineCredits(
      amount: 1,
      contentIds: ['c1'],
    );

    // Verify batch ID is in SQLite
    final config = await db.securityConfigDao.get();
    expect(config.creditSpentBatchId, isNotNull);
    expect(config.creditSpentBatchId, equals(batchId));
  });

  test('server state overwrites local state', () async {
    // Spend some credits locally
    await creditService.spendOfflineCredits(amount: 3, contentIds: ['a', 'b', 'c']);

    // Server returns authoritative state
    await creditService.applyServerCreditState(
      offlineCredits: 5,
      spentIds: ['x', 'y'],
      serverCounter: 5,
    );

    final config = await db.securityConfigDao.get();
    expect(config.offlineCredits, equals(5));
    expect(config.creditServerCounter, equals(5));
    expect(config.creditSpentBatchId, isNull); // cleared after sync
  });
}