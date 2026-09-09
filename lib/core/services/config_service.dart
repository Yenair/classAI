// lib/core/services/config_service.dart
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Service that fetches remote app configuration from the `get-config` Edge
/// Function, caches it in [SharedPreferences], and exposes typed getters for
/// each known config key.
///
/// The config is fetched once on first access and after every successful sync.
class ConfigService {
  static const String _cachePrefix = 'config_';

  final SupabaseClient _client;
  Map<String, String> _cache = {};
  bool _loaded = false;

  ConfigService({SupabaseClient? client})
      : _client = client ?? Supabase.instance.client;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Fetches the latest config from the server and updates the in-memory and
  /// disk cache. Returns true if the fetch succeeded.
  Future<bool> refresh() async {
    try {
      final response = await _client.functions
          .invoke('get-config')
          .timeout(const Duration(seconds: 10));
      final data = response.data as Map<String, dynamic>?;
      if (data == null) return false;

      final prefs = await SharedPreferences.getInstance();
      final map = <String, String>{};
      for (final entry in data.entries) {
        final value = entry.value?.toString() ?? '';
        map[entry.key] = value;
        await prefs.setString('$_cachePrefix${entry.key}', value);
      }
      _cache = map;
      _loaded = true;
      return true;
    } catch (e) {
      debugPrint('[ConfigService] refresh failed: $e');
      // Fall back to disk cache if available
      if (!_loaded) {
        await _loadFromDisk();
      }
      return false;
    }
  }

  /// Returns the cached string value for [key], or [defaultValue] if absent.
  String getString(String key, {String defaultValue = ''}) {
    return _cache[key] ?? defaultValue;
  }

  /// Returns the cached int value for [key], or [defaultValue] if absent/parse
  /// fails.
  int getInt(String key, {int defaultValue = 0}) {
    final raw = _cache[key];
    if (raw == null) return defaultValue;
    return int.tryParse(raw) ?? defaultValue;
  }

  /// Returns the cached bool value for [key], or [defaultValue] if absent.
  bool getBool(String key, {bool defaultValue = false}) {
    final raw = _cache[key];
    if (raw == null) return defaultValue;
    return raw.toLowerCase() == 'true';
  }

  /// Parses a JSON map from the cached string value for [key].
  /// Returns an empty map on failure.
  Map<String, dynamic> getJsonMap(String key) {
    final raw = _cache[key];
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = json.decode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  /// Parses a JSON list from the cached string value for [key].
  /// All string elements are lowercased for consistent tier comparison.
  /// Returns an empty list on failure.
  List<String> getJsonList(String key) {
    final raw = _cache[key];
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded
            .map((e) => e.toString().toLowerCase())
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ---------------------------------------------------------------------------
  // Typed getters for known config keys
  // ---------------------------------------------------------------------------

  /// Subscription prices as a map: { "basic": 49999, ... }
  Map<String, dynamic> get subscriptionPrices => getJsonMap('subscription_prices');

  // NOTE (R2 Block 4): daily_preview_limits and daily_generation_limits
  // were removed — the unified dailyCreditsLimit getter is the only
  // generation/preview quota source now.

  /// Unified daily credit limits per tier:
  /// { "free": 3, "basic": 1, "standard": 3, "elite": -1 }
  /// One pool covering AI generation and vault acquisitions.
  /// -1 means unlimited (elite).
  Map<String, dynamic> get dailyCreditsLimit => getJsonMap('daily_credits_limit');

  /// PDF export limits per tier: { "free": 1, "basic": 3, ... }
  Map<String, dynamic> get pdfExportLimits => getJsonMap('pdf_export_limits');

  /// Teacher seat limits per tier: { "free": 5, "basic": 10, "standard": 20, "elite": 100 }
  Map<String, dynamic> get teacherSeatLimits =>
      getJsonMap('teacher_seat_limits');

  /// Lesson/exam storage limits per tier: { "free": 100, "basic": 200, "standard": 500, "elite": -1 }
  Map<String, dynamic> get lessonStorageLimits =>
      getJsonMap('lesson_storage_limits');

  /// Allowed tiers for AI diagrams feature: e.g. ["elite"]
  List<String> get aiDiagramsAllowedTiers =>
      getJsonList('ai_diagrams_allowed_tiers');

  /// Allowed tiers for exam generation feature: e.g. ["standard", "elite"].
  /// Defaults to standard + elite when the key is absent/unseeded so a
  /// missing remote key never silently locks everyone out — and never
  /// re-opens the gate to free/basic.
  List<String> get examGenerationAllowedTiers {
    final tiers = getJsonList('exam_generation_allowed_tiers');
    if (tiers.isEmpty) return ['standard', 'elite'];
    return tiers;
  }

  /// Allowed tiers for lesson assessment-question generation (Phase 2).
  /// Defaults to standard + elite when the key is absent/unseeded so a
  /// missing remote key never silently locks everyone out.
  List<String> get assessmentGenerationAllowedTiers {
    final tiers = getJsonList('assessment_generation_allowed_tiers');
    if (tiers.isEmpty) return ['standard', 'elite'];
    return tiers;
  }

  /// Allowed tiers for bulk PDF export feature: e.g. ["standard", "elite"]
  List<String> get bulkPdfExportAllowedTiers =>
      getJsonList('bulk_pdf_export_allowed_tiers');

  /// Allowed tiers for sync health tab: e.g. ["elite"]
  List<String> get syncHealthAllowedTiers {
    final tiers = getJsonList('sync_health_allowed_tiers');
    if (tiers.isEmpty) return ['elite'];
    return tiers;
  }

  /// Per-tier subject restrictions.
  /// Map of tier name → list of allowed subject names.
  /// e.g. { "free": ["Mathematics","English"], "basic": ["*"], ... }
  /// An empty or missing entry means all subjects are allowed.
  Map<String, dynamic> get topicRestrictionsByTier =>
      getJsonMap('topic_restrictions_by_tier');

  /// Returns true if [tier] is allowed to generate content for [subject].
  /// When no restrictions are configured (empty map), all subjects are allowed.
  /// A wildcard "*" in the allowed list means all subjects.
  bool isSubjectAllowedForTier(String tier, String subject) {
    final restrictions = topicRestrictionsByTier;
    if (restrictions.isEmpty) return true; // no restrictions configured
    final allowed = restrictions[tier];
    if (allowed == null || (allowed is List && allowed.isEmpty)) return true;
    if (allowed is List) {
      final lower = allowed.map((e) => e.toString().toLowerCase()).toList();
      if (lower.contains('*')) return true;
      return lower.contains(subject.toLowerCase());
    }
    return true;
  }

  bool get featureVaultPublishing =>
      getBool('feature_vault_publishing', defaultValue: true);

  bool get featureSchemeGeneration =>
      getBool('feature_scheme_generation', defaultValue: true);

  String get announcementText => getString('announcement_text');

  String get minAppVersion => getString('min_app_version', defaultValue: '1.0.0');

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<void> _loadFromDisk() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_cachePrefix));
      for (final key in keys) {
        final configKey = key.substring(_cachePrefix.length);
        _cache[configKey] = prefs.getString(key) ?? '';
      }
      _loaded = true;
    } catch (e) {
      debugPrint('[ConfigService] _loadFromDisk failed: $e');
    }
  }
}
