// Phase 4 (item 4) — the daily-limit exception message includes the day's
// usage, e.g. "Daily credit limit reached (1/1 today). Try again tomorrow.",
// so the editor error toasts show the user where they stand.
//
// R2 Block 1: checkDailyLimit now spends from the unified daily credit pool
// (checkAndSpendDailyCredits) instead of the legacy generation counter.
//
// checkDailyLimit never touches Supabase; the mock client only satisfies the
// AiService constructor (which otherwise reads Supabase.instance). The credit
// balance is seeded by writing the security_config row directly, mirroring
// test/database/security_config_dao_test.dart.
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/ai_service.dart';
import 'package:classai/core/services/config_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

/// Fake ConfigService serving [values] with no Supabase/network I/O
/// (same pattern as test/database/security_config_dao_test.dart).
class FakeConfigService extends Fake implements ConfigService {
  FakeConfigService(this.values);
  final Map<String, dynamic> values;

  @override
  Map<String, dynamic> get dailyCreditsLimit =>
      values['daily_credits_limit'] as Map<String, dynamic>? ?? {};

  @override
  Future<bool> refresh() async => false;
}

void main() {
  late AppDatabase db;
  late MockSupabaseClient mockSupabase;

  /// Rewrites the singleton security_config row's unified credit balance.
  Future<void> seedCredits({
    required int offlineCredits,
    required String dailyCreditsDate,
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

  setUp(() async {
    mockSupabase = MockSupabaseClient();
    db = AppDatabase.forTesting();
    addTearDown(db.close);
  });

  group('AiService.checkDailyLimit limit-reached message', () {
    test('blocked basic-tier attempt reports "(1/1 today)"', () async {
      // Exhaust the basic-tier unified pool (1 credit) for today. The
      // blocked attempt does not spend, so used stays at the full limit.
      await seedCredits(offlineCredits: 0, dailyCreditsDate: today());

      final aiService = AiService(supabase: mockSupabase, db: db);

      await expectLater(
        aiService.checkDailyLimit('basic'),
        throwsA(
          isA<AiGenerationException>().having(
            (e) => e.message,
            'message',
            'Daily credit limit reached (1/1 today). Try again tomorrow.',
          ),
        ),
      );
    });

    test('usage pair follows the remote-config pool limit', () async {
      // Remote config widens basic to 2/day; exhaust it.
      db.securityConfigDao.setConfigService(FakeConfigService({
        'daily_credits_limit': {'basic': 2},
      }));
      await seedCredits(offlineCredits: 0, dailyCreditsDate: today());

      final aiService = AiService(supabase: mockSupabase, db: db);

      await expectLater(
        aiService.checkDailyLimit('basic'),
        throwsA(
          isA<AiGenerationException>().having(
            (e) => e.message,
            'message',
            'Daily credit limit reached (2/2 today). Try again tomorrow.',
          ),
        ),
      );
    });

    test('allowed attempt returns true and spends one credit', () async {
      await seedCredits(offlineCredits: 1, dailyCreditsDate: today());

      final aiService = AiService(supabase: mockSupabase, db: db);

      expect(await aiService.checkDailyLimit('basic'), isTrue);

      final row = await db.select(db.securityConfig).getSingle();
      expect(row.offlineCredits, 0);
      expect(row.dailyCreditsDate, today());
    });
  });
}
