// Phase 5 (item 1) — unit tests for ConfigService.isSubjectAllowedForTier.
//
// ConfigService fetches config from the `get-config` Edge Function and falls
// back to the SharedPreferences disk cache on failure. To seed config values
// without any network I/O we mock SharedPreferences with `config_<key>`
// entries and use a mock Supabase client whose `get-config` call fails fast
// (same pattern as test/ui/reader_layout_test.dart).
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:classai/core/services/config_service.dart';

class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockFunctionsClient extends Mock implements FunctionsClient {}

/// Mock Supabase client whose `get-config` function fails fast so
/// [ConfigService.refresh] falls back to the (mocked) disk cache.
MockSupabaseClient buildMockSupabase() {
  final supabase = MockSupabaseClient();
  final functions = MockFunctionsClient();
  when(() => functions.invoke('get-config')).thenThrow(
    FunctionException(status: 500),
  );
  when(() => supabase.functions).thenReturn(functions);
  return supabase;
}

/// Builds a ConfigService whose cache is seeded from [configValues].
/// Keys are raw config keys (without the `config_` cache prefix).
Future<ConfigService> buildConfigService(
  Map<String, String> configValues,
) async {
  SharedPreferences.setMockInitialValues({
    for (final entry in configValues.entries)
      'config_${entry.key}': entry.value,
  });
  final service = ConfigService(client: buildMockSupabase());
  // refresh() fails against the mock and falls back to the seeded disk cache.
  await service.refresh();
  return service;
}

void main() {
  group('isSubjectAllowedForTier', () {
    test('allows every subject when no restrictions are configured', () async {
      final config = await buildConfigService({});

      expect(config.topicRestrictionsByTier, isEmpty);
      expect(config.isSubjectAllowedForTier('free', 'Mathematics'), isTrue);
      expect(config.isSubjectAllowedForTier('free', 'Chemistry'), isTrue);
      expect(config.isSubjectAllowedForTier('basic', 'Physics'), isTrue);
    });

    test('allows every subject when the key is empty JSON', () async {
      final config = await buildConfigService({
        'topic_restrictions_by_tier': '{}',
      });

      expect(config.isSubjectAllowedForTier('free', 'Biology'), isTrue);
    });

    test('allows every subject for a tier missing from the map', () async {
      final config = await buildConfigService({
        'topic_restrictions_by_tier': jsonEncode({
          'free': ['Mathematics', 'English'],
        }),
      });

      // 'basic' has no entry -> unrestricted.
      expect(config.isSubjectAllowedForTier('basic', 'Chemistry'), isTrue);
    });

    test('enforces a specific allowed list per tier', () async {
      final config = await buildConfigService({
        'topic_restrictions_by_tier': jsonEncode({
          'free': ['Mathematics', 'English'],
          'basic': ['*'],
          'standard': ['*'],
          'elite': ['*'],
        }),
      });

      // free: only listed subjects pass.
      expect(config.isSubjectAllowedForTier('free', 'Mathematics'), isTrue);
      expect(config.isSubjectAllowedForTier('free', 'English'), isTrue);
      expect(config.isSubjectAllowedForTier('free', 'Chemistry'), isFalse);

      // basic: wildcard unlocks all subjects.
      expect(config.isSubjectAllowedForTier('basic', 'Chemistry'), isTrue);
      expect(config.isSubjectAllowedForTier('basic', 'Physics'), isTrue);
    });

    test('matches subjects case-insensitively', () async {
      final config = await buildConfigService({
        'topic_restrictions_by_tier': jsonEncode({
          'free': ['Mathematics', 'English'],
        }),
      });

      expect(config.isSubjectAllowedForTier('free', 'mathematics'), isTrue);
      expect(config.isSubjectAllowedForTier('free', 'ENGLISH'), isTrue);
      // Near-miss subjects must not slip through.
      expect(config.isSubjectAllowedForTier('free', 'Maths'), isFalse);
    });

    test('treats an empty allowed list as unrestricted', () async {
      final config = await buildConfigService({
        'topic_restrictions_by_tier': jsonEncode({
          'free': <String>[],
        }),
      });

      expect(config.isSubjectAllowedForTier('free', 'Chemistry'), isTrue);
    });

    test('treats a non-list entry as unrestricted', () async {
      final config = await buildConfigService({
        'topic_restrictions_by_tier': jsonEncode({
          'free': 'everything',
        }),
      });

      expect(config.isSubjectAllowedForTier('free', 'Chemistry'), isTrue);
    });

    test('allows every subject when the cached value is malformed JSON',
        () async {
      final config = await buildConfigService({
        'topic_restrictions_by_tier': '{not valid json',
      });

      expect(config.topicRestrictionsByTier, isEmpty);
      expect(config.isSubjectAllowedForTier('free', 'Chemistry'), isTrue);
    });
  });
}
