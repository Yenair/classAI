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

  // ---------------------------------------------------------------------------
  // Typed getters for known config keys
  // ---------------------------------------------------------------------------

  /// Subscription prices as a map: { "basic": 49999, ... }
  Map<String, dynamic> get subscriptionPrices => getJsonMap('subscription_prices');

  /// Daily preview limits per tier: { "free": 0, "basic": 10, ... }
  Map<String, dynamic> get dailyPreviewLimits =>
      getJsonMap('daily_preview_limits');

  /// PDF export limits per tier: { "free": 1, "basic": 3, ... }
  Map<String, dynamic> get pdfExportLimits => getJsonMap('pdf_export_limits');

  /// Teacher seat limits per tier: { "free": 5, "basic": 10, "standard": 20, "elite": 100 }
  Map<String, dynamic> get teacherSeatLimits =>
      getJsonMap('teacher_seat_limits');

  /// Lesson/exam storage limits per tier: { "free": 10, "basic": 20, "standard": 50, "elite": -1 }
  Map<String, dynamic> get lessonStorageLimits =>
      getJsonMap('lesson_storage_limits');

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
