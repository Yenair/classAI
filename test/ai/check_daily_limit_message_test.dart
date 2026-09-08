// Phase 4 (item 4) — the daily-limit exception message includes the day's
// usage, e.g. "Daily generation limit reached (5/5 today). Try again
// tomorrow.", so the editor error toasts show the user where they stand.
//
// checkDailyLimit never touches Supabase; the mock client only satisfies the
// AiService constructor (which otherwise reads Supabase.instance). Counters
// are seeded by writing the security_config row directly, mirroring
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
  Map<String, dynamic> get dailyGenerationLimits =>
      values['daily_generation_limits'] as Map<String, dynamic>? ?? {};

  @override
  Future<bool> refresh() async => false;
}

void main() {
  late AppDatabase db;
  late MockSupabaseClient mockSupabase;

  /// Rewrites the singleton security_config row's generation counter.
  Future<void> seedGenerations({
    required int dailyGenerations,
    required String dailyGenerationDate,
  }) async {
    await db.update(db.securityConfig).write(
          SecurityConfigCompanion(
            dailyGenerations: Value(dailyGenerations),
            dailyGenerationDate: Value(dailyGenerationDate),
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
    test('blocked basic-tier attempt reports "(5/5 today)"', () async {
      // Exhaust the basic-tier default limit (5) for today. The blocked
      // attempt does not increment, so used stays at the full limit.
      await seedGenerations(
        dailyGenerations: 5,
        dailyGenerationDate: today(),
      );

      final aiService = AiService(supabase: mockSupabase, db: db);

      await expectLater(
        aiService.checkDailyLimit('basic'),
        throwsA(
          isA<AiGenerationException>().having(
            (e) => e.message,
            'message',
            'Daily generation limit reached (5/5 today). Try again tomorrow.',
          ),
        ),
      );
    });

    test('usage pair follows the remote-config limit', () async {
      // Remote config narrows basic to 2/day; exhaust it.
      db.securityConfigDao.setConfigService(FakeConfigService({
        'daily_generation_limits': {'basic': 2},
      }));
      await seedGenerations(
        dailyGenerations: 2,
        dailyGenerationDate: today(),
      );

      final aiService = AiService(supabase: mockSupabase, db: db);

      await expectLater(
        aiService.checkDailyLimit('basic'),
        throwsA(
          isA<AiGenerationException>().having(
            (e) => e.message,
            'message',
            'Daily generation limit reached (2/2 today). Try again tomorrow.',
          ),
        ),
      );
    });

    test('allowed attempt returns true and increments the counter', () async {
      await seedGenerations(
        dailyGenerations: 1,
        dailyGenerationDate: today(),
      );

      final aiService = AiService(supabase: mockSupabase, db: db);

      expect(await aiService.checkDailyLimit('basic'), isTrue);

      final row = await db.select(db.securityConfig).getSingle();
      expect(row.dailyGenerations, 2);
      expect(row.dailyGenerationDate, today());
    });
  });
}
