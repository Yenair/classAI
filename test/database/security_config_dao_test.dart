// Phase 5 (item 2) — unit tests for SecurityConfigDao daily generation limits.
//
// Verifies that `checkAndIncrementDailyGenerations` uses the *generation*
// limit (not the preview limit), resets on a new day, returns false once the
// limit is exceeded, and that `getRemainingDailyGenerations` reports the
// correct remaining count.
//
// Uses an in-memory drift database (`AppDatabase.forTesting()`); its
// beforeOpen callback seeds the singleton `security_config` row. Counters are
// seeded by writing the row directly (SecurityConfigCompanion), because
// `updateConfig()` exposes no dailyGenerations parameters.
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

  /// The DAO reads the typed getter, which in production wraps
  /// getJsonMap('daily_generation_limits').
  @override
  Map<String, dynamic> get dailyGenerationLimits =>
      values['daily_generation_limits'] as Map<String, dynamic>? ?? {};

  @override
  Future<bool> refresh() async => false;
}

void main() {
  late AppDatabase db;
  late SecurityConfigDao dao;

  /// Rewrites the singleton security_config row with the given counter state.
  Future<void> seedCounters({
    required int dailyGenerations,
    String? dailyGenerationDate,
  }) async {
    await db.update(db.securityConfig).write(
          SecurityConfigCompanion(
            dailyGenerations: Value(dailyGenerations),
            dailyGenerationDate: Value(dailyGenerationDate),
          ),
        );
  }

  /// Re-reads the singleton row's generation counter state.
  Future<(int, String?)> readGenerations() async {
    final row = await db.select(db.securityConfig).getSingle();
    return (row.dailyGenerations, row.dailyGenerationDate);
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

  group('checkAndIncrementDailyGenerations', () {
    test('uses the generation limit (5), not the preview limit (10)',
        () async {
      // Hardcoded defaults: basic = 5 generations, 10 previews.
      for (var i = 0; i < 5; i++) {
        expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
            isTrue, reason: 'generation ${i + 1} of 5 should be allowed');
      }

      final (count, date) = await readGenerations();
      expect(count, 5);
      expect(date, today());

      // 6th generation exceeds the generation limit even though a
      // preview-limit-based check (10) would still allow it.
      expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isFalse);
    });

    test('resets the counter on a new day', () async {
      // Previous day: the basic-tier counter was exhausted (5/5).
      await seedCounters(
        dailyGenerations: 5,
        dailyGenerationDate: yesterday(),
      );

      expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isTrue);

      final (count, date) = await readGenerations();
      expect(count, 1);
      expect(date, today());
    });

    test('does not increment the counter when the limit is exceeded',
        () async {
      await seedCounters(
        dailyGenerations: 5,
        dailyGenerationDate: today(),
      );

      expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isFalse);

      final (count, date) = await readGenerations();
      expect(count, 5);
      expect(date, today());
    });

    test('elite tier (-1) is unlimited', () async {
      for (var i = 0; i < 12; i++) {
        expect(
          await dao.checkAndIncrementDailyGenerations(tier: 'elite'),
          isTrue,
          reason: 'elite should never hit the limit (call ${i + 1})',
        );
      }

      final (count, _) = await readGenerations();
      expect(count, 12);
    });

    test('free tier (limit 0) is currently not enforced by the DAO',
        () async {
      // NOTE: the DAO guard is `limit > 0 && newCount >= limit`, so a limit
      // of 0 never blocks at this layer — identical to the preview logic.
      // Free-tier generation is gated upstream via allowed-tiers config
      // (e.g. exam_generation_allowed_tiers) rather than the daily counter.
      // This test documents that behavior; flip it if the DAO is ever
      // changed to enforce limit == 0.
      expect(await dao.checkAndIncrementDailyGenerations(tier: 'free'),
          isTrue);
    });

    test('honors daily_generation_limits from remote config', () async {
      dao.setConfigService(FakeConfigService({
        'daily_generation_limits': {'free': 0, 'basic': 2},
      }));

      expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isTrue);
      expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isTrue);
      expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isFalse);
    });

    test('falls back to hardcoded defaults when the config key is absent',
        () async {
      dao.setConfigService(FakeConfigService({}));

      // basic default = 5.
      for (var i = 0; i < 5; i++) {
        expect(
          await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isTrue,
          reason: 'generation ${i + 1} of 5 should be allowed',
        );
      }
      expect(await dao.checkAndIncrementDailyGenerations(tier: 'basic'),
          isFalse);
    });

    test('generation counter is independent of the preview counter',
        () async {
      expect(await dao.checkAndIncrementDailyGenerations(tier: 'standard'),
          isTrue);
      expect(await dao.checkAndIncrementDailyGenerations(tier: 'standard'),
          isTrue);

      final row = await db.select(db.securityConfig).getSingle();
      expect(row.dailyGenerations, 2);
      expect(row.dailyGenerationDate, today());
      expect(row.dailyPreviewCount, 0);
      expect(row.dailyPreviewDate, isNull);
    });
  });

  group('getRemainingDailyGenerations', () {
    test('returns limit minus used count for the same day', () async {
      await seedCounters(
        dailyGenerations: 3,
        dailyGenerationDate: today(),
      );

      expect(await dao.getRemainingDailyGenerations(tier: 'basic'), 2);
    });

    test('returns the full limit when the stored date is stale', () async {
      await seedCounters(
        dailyGenerations: 5,
        dailyGenerationDate: yesterday(),
      );

      expect(await dao.getRemainingDailyGenerations(tier: 'basic'), 5);
    });

    test('returns -1 for the unlimited elite tier', () async {
      await seedCounters(
        dailyGenerations: 999,
        dailyGenerationDate: today(),
      );

      expect(await dao.getRemainingDailyGenerations(tier: 'elite'), -1);
    });

    test('never returns a negative count when over the limit', () async {
      await seedCounters(
        dailyGenerations: 9,
        dailyGenerationDate: today(),
      );

      expect(await dao.getRemainingDailyGenerations(tier: 'basic'), 0);
    });
  });

  group('getDailyGenerationLimit', () {
    test('returns the hardcoded defaults when no config service is set',
        () async {
      expect(dao.getDailyGenerationLimit('free'), 0);
      expect(dao.getDailyGenerationLimit('basic'), 5);
      expect(dao.getDailyGenerationLimit('standard'), 10);
      expect(dao.getDailyGenerationLimit('elite'), -1);
    });

    test('returns the remote-config value when set', () async {
      dao.setConfigService(FakeConfigService({
        'daily_generation_limits': {'basic': 7},
      }));

      expect(dao.getDailyGenerationLimit('basic'), 7);
      // Other tiers still fall back to their defaults.
      expect(dao.getDailyGenerationLimit('standard'), 10);
    });

    test('falls back to defaults when the config key is absent', () async {
      dao.setConfigService(FakeConfigService({}));

      expect(dao.getDailyGenerationLimit('basic'), 5);
    });

    test('falls back to the default for an unknown tier', () async {
      expect(dao.getDailyGenerationLimit('unknown'), 5);
    });

    test('the DAO instance is stable so injected config survives', () async {
      // Regression: securityConfigDao used to be a getter constructing a new
      // instance per access, which dropped the ConfigService wired in
      // main.dart — remote limits were silently ignored app-wide.
      expect(db.securityConfigDao, same(dao));

      db.securityConfigDao.setConfigService(FakeConfigService({
        'daily_generation_limits': {'basic': 7},
      }));
      // A fresh access must still see the injected config.
      expect(db.securityConfigDao.getDailyGenerationLimit('basic'), 7);
    });
  });
}
