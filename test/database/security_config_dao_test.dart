// R2 Block 4 (2H.1 / 2H.2) — unit tests for the SecurityConfigDao unified
// daily-credit pool.
//
// Verifies that `checkAndSpendDailyCredits` enforces the tier limit with
// balance semantics (reset on a new day, decrement on spend), that elite
// (-1) is unlimited, and that `getRemainingDailyCredits` reports the
// remaining count read-only.
//
// The legacy generation/preview counter tests were removed with the legacy
// counter methods in Block 4 (2B.7/2B.8) — the unified pool is the only
// generation/preview gate now.
//
// Uses an in-memory drift database (`AppDatabase.forTesting()`); its
// beforeOpen callback seeds the singleton `security_config` row. Balances
// are seeded by writing the row directly (SecurityConfigCompanion).
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/database/daos/security_config_dao.dart';
import 'package:classai/core/services/config_service.dart';

/// Fake ConfigService that serves [values] without any Supabase/network I/O.
///
/// `refresh()` is a no-op returning false, mirroring an offline device whose
/// in-memory cache was populated from disk by the app at startup.
class FakeConfigService extends Fake implements ConfigService {
  FakeConfigService(this.values);
  final Map<String, dynamic> values;

  /// Unified daily credit pool (R2), produced from
  /// getJsonMap('daily_credits_limit').
  @override
  Map<String, dynamic> get dailyCreditsLimit =>
      values['daily_credits_limit'] as Map<String, dynamic>? ?? {};

  @override
  Future<bool> refresh() async => false;
}

void main() {
  late AppDatabase db;
  late SecurityConfigDao dao;

  /// Rewrites the singleton security_config row's unified credit balance.
  Future<void> seedCredits({
    required int offlineCredits,
    String? dailyCreditsDate,
  }) async {
    await db.update(db.securityConfig).write(
          SecurityConfigCompanion(
            offlineCredits: Value(offlineCredits),
            dailyCreditsDate: Value(dailyCreditsDate),
          ),
        );
  }

  /// Today's date in the same format the DAO stores: yyyy-MM-dd.
  String today() => DateTime.now().toIso8601String().split('T').first;

  /// Yesterday's date in the same format the DAO stores: yyyy-MM-dd.
  String yesterday() =>
      DateTime.now().subtract(const Duration(days: 1)).toIso8601String().split('T').first;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = AppDatabase.forTesting();
    dao = db.securityConfigDao;
  });

  tearDown(() async {
    await db.close();
  });

  // ------------------------------------------------------------------------
  // R2 Block 1 (2H.1 / 2H.2) — unified daily credits
  // ------------------------------------------------------------------------

  group('checkAndSpendDailyCredits (2H.1)', () {
    test('spends 1 credit and stamps today\'s date', () async {
      await seedCredits(offlineCredits: 3, dailyCreditsDate: today());

      expect(await dao.checkAndSpendDailyCredits(tier: 'standard'), isTrue);

      final row = await db.select(db.securityConfig).getSingle();
      expect(row.offlineCredits, 2);
      expect(row.dailyCreditsDate, today());
    });

    test('resets to the tier limit on a new day', () async {
      // Yesterday the balance was drained to 0; a new day restores it.
      await seedCredits(offlineCredits: 0, dailyCreditsDate: yesterday());

      expect(await dao.checkAndSpendDailyCredits(tier: 'basic'), isTrue);

      final row = await db.select(db.securityConfig).getSingle();
      // basic limit = 1: reset to 1, then spend 1 -> 0.
      expect(row.offlineCredits, 0);
      expect(row.dailyCreditsDate, today());
    });

    test('returns false and writes nothing when balance is exhausted',
        () async {
      await seedCredits(offlineCredits: 0, dailyCreditsDate: today());

      expect(await dao.checkAndSpendDailyCredits(tier: 'standard'), isFalse);

      final row = await db.select(db.securityConfig).getSingle();
      expect(row.offlineCredits, 0);
      expect(row.dailyCreditsDate, today());
    });

    test('cost > 1 is charged fully (no silent clamping at the DAO layer)',
        () async {
      await seedCredits(offlineCredits: 3, dailyCreditsDate: today());

      expect(
        await dao.checkAndSpendDailyCredits(tier: 'standard', cost: 2),
        isTrue,
      );

      final row = await db.select(db.securityConfig).getSingle();
      expect(row.offlineCredits, 1);
    });

    test('honors daily_credits_limit from remote config', () async {
      dao.setConfigService(FakeConfigService({
        'daily_credits_limit': {'basic': 2},
      }));
      await seedCredits(offlineCredits: 2, dailyCreditsDate: today());

      expect(await dao.checkAndSpendDailyCredits(tier: 'basic'), isTrue);
      expect(await dao.checkAndSpendDailyCredits(tier: 'basic'), isTrue);
      expect(await dao.checkAndSpendDailyCredits(tier: 'basic'), isFalse);
    });

    test('elite tier (-1) is unlimited and never blocked', () async {
      await seedCredits(offlineCredits: 0, dailyCreditsDate: today());

      for (var i = 0; i < 12; i++) {
        expect(
          await dao.checkAndSpendDailyCredits(tier: 'elite'),
          isTrue,
          reason: 'elite should never hit the limit (call ${i + 1})',
        );
      }
    });

    test('falls back to hardcoded defaults when the config key is absent',
        () async {
      dao.setConfigService(FakeConfigService({}));
      await seedCredits(offlineCredits: 1, dailyCreditsDate: today());

      // basic default = 1: first spend OK, second blocked.
      expect(await dao.checkAndSpendDailyCredits(tier: 'basic'), isTrue);
      expect(await dao.checkAndSpendDailyCredits(tier: 'basic'), isFalse);
    });
  });

  group('getRemainingDailyCredits (2H.2)', () {
    test('returns the stored balance for the same day', () async {
      await seedCredits(offlineCredits: 2, dailyCreditsDate: today());

      expect(await dao.getRemainingDailyCredits(tier: 'standard'), 2);
    });

    test('returns the full limit when the stored date is stale', () async {
      await seedCredits(offlineCredits: 0, dailyCreditsDate: yesterday());

      expect(await dao.getRemainingDailyCredits(tier: 'standard'), 3);
    });

    test('returns -1 for the unlimited elite tier', () async {
      await seedCredits(offlineCredits: 0, dailyCreditsDate: today());

      expect(await dao.getRemainingDailyCredits(tier: 'elite'), -1);
    });

    test('never returns a negative count when the balance is over-drawn',
        () async {
      // Legacy/multi-device race can leave a negative balance; the
      // read-only getter must clamp to 0 rather than surface -N.
      await seedCredits(offlineCredits: -5, dailyCreditsDate: today());

      expect(await dao.getRemainingDailyCredits(tier: 'basic'), 0);
    });

    test('is read-only: never writes balance or date', () async {
      await seedCredits(offlineCredits: 2, dailyCreditsDate: yesterday());

      expect(await dao.getRemainingDailyCredits(tier: 'standard'), 3);

      final row = await db.select(db.securityConfig).getSingle();
      expect(row.offlineCredits, 2); // untouched
      expect(row.dailyCreditsDate, yesterday()); // untouched
    });
  });

  group('getDailyCreditLimit', () {
    test('returns the hardcoded defaults when no config service is set',
        () async {
      expect(dao.getDailyCreditLimit('free'), 3);
      expect(dao.getDailyCreditLimit('basic'), 1);
      expect(dao.getDailyCreditLimit('standard'), 3);
      expect(dao.getDailyCreditLimit('elite'), -1);
    });

    test('returns the remote-config value when set', () async {
      dao.setConfigService(FakeConfigService({
        'daily_credits_limit': {'basic': 7},
      }));

      expect(dao.getDailyCreditLimit('basic'), 7);
      // Other tiers still fall back to their defaults.
      expect(dao.getDailyCreditLimit('standard'), 3);
    });

    test('falls back to defaults when the config key is absent', () async {
      dao.setConfigService(FakeConfigService({}));

      expect(dao.getDailyCreditLimit('basic'), 1);
    });

    test('falls back to the default for an unknown tier', () async {
      expect(dao.getDailyCreditLimit('unknown'), 1);
    });

    test('the DAO instance is stable so injected config survives', () async {
      // Regression: securityConfigDao used to be a getter constructing a new
      // instance per access, which dropped the ConfigService wired in
      // main.dart — remote limits were silently ignored app-wide.
      expect(db.securityConfigDao, same(dao));

      db.securityConfigDao.setConfigService(FakeConfigService({
        'daily_credits_limit': {'basic': 7},
      }));
      // A fresh access must still see the injected config.
      expect(db.securityConfigDao.getDailyCreditLimit('basic'), 7);
    });
  });
}
