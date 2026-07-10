import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import 'package:drift/drift.dart' show Value;
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Provider that manages the app's theme mode.
/// Saves the preference locally via SharedPreferences and remotely
/// via Supabase (on the teachers table) when a teacher or admin is logged in.
class ThemeNotifier extends Notifier<ThemeMode> {
  static const _themeKey = 'theme_mode';

  supabase_pkg.GoTrueClient get _auth =>
      supabase_pkg.Supabase.instance.client.auth;

  @override
  ThemeMode build() {
    // Default to system theme
    return ThemeMode.system;
  }

  Future<void> loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final themeIndex = prefs.getInt(_themeKey);
    if (themeIndex != null) {
      state = ThemeMode.values[themeIndex];
    }
  }

  /// Apply the theme mode from a teacher's stored preference (e.g. on login).
  /// Only applies the server value if there is NO locally saved preference,
  /// so the user's toggle is never overwritten on app restart.
  Future<void> applyTeacherThemeMode(String? themeModeStr) async {
    final prefs = await SharedPreferences.getInstance();
    final localIndex = prefs.getInt(_themeKey);

    // If user has a locally saved preference, respect it over the server value
    if (localIndex != null) {
      state = ThemeMode.values[localIndex];
      return;
    }

    final mode = _parseThemeMode(themeModeStr);
    state = mode;
    await prefs.setInt(_themeKey, mode.index);
  }

  ThemeMode _parseThemeMode(String? themeModeStr) {
    switch (themeModeStr) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setTheme(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeKey, mode.index);

    // Persist to the local teachers table so the choice survives app restarts
    // even if SharedPreferences is cleared. Also ensures that on re-login
    // the locally stored theme is applied correctly.
    await _saveThemeToLocalDb(mode);

    // Sync to Supabase if there's an active session
    await _syncThemeToServer(mode);
  }

  Future<void> _saveThemeToLocalDb(ThemeMode mode) async {
    try {
      final db = ref.read(databaseProvider);

      // For admins, _auth.currentUser may be null (custom JWT auth).
      // Look up the teacher from the local DB instead.
      final teachers = await db.teachersDao.getAll();
      if (teachers.isEmpty) return;

      // Use the first active teacher record as the current user.
      // In practice there is usually only one teacher per device for admins.
      final teacher = teachers.firstWhere(
        (t) => t.isActive,
        orElse: () => teachers.first,
      );

      String themeValue;
      switch (mode) {
        case ThemeMode.light:
          themeValue = 'light';
          break;
        case ThemeMode.dark:
          themeValue = 'dark';
          break;
        case ThemeMode.system:
          themeValue = 'system';
          break;
      }

      await (db.update(db.teachers)
            ..where((t) => t.localId.equals(teacher.localId)))
          .write(TeachersCompanion(
        themeMode: Value(themeValue),
        updatedAt: Value(DateTime.now()),
      ));
    } catch (e) {
      debugPrint('[ThemeNotifier] Failed to save theme to local DB: $e');
    }
  }

  Future<void> _syncThemeToServer(ThemeMode mode) async {
    try {
      final client = supabase_pkg.Supabase.instance.client;
      final userId = _auth.currentUser?.id ?? _auth.currentSession?.user.id;
      if (userId == null || userId.isEmpty) return;

      // Determine the theme string value
      String themeValue;
      switch (mode) {
        case ThemeMode.light:
          themeValue = 'light';
          break;
        case ThemeMode.dark:
          themeValue = 'dark';
          break;
        case ThemeMode.system:
          themeValue = 'system';
          break;
      }

      // Update the teachers table via the Supabase client using service-role
      // edge function call or direct update via the user's own JWT
      // Since the teachers table has row-level security, we use a direct
      // update with the user's own auth token
      await client.from('teachers').update({
        'theme_mode': themeValue,
      }).eq('id', userId);
    } catch (e) {
      // Silently fail — the local preference is already saved
      // and will be re-synced on next login
      debugPrint('[ThemeNotifier] Failed to sync theme to server: $e');
    }
  }

  String themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> toggleTheme() async {
    final nextMode = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    await setTheme(nextMode);
  }
}

final themeProvider = NotifierProvider<ThemeNotifier, ThemeMode>(
  ThemeNotifier.new,
);
