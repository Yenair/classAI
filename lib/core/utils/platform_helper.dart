import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlatformHelper {
  /// Returns `true` for Editor layout (desktop/large tablet), `false` for Reader layout (phone/small tablet).
  ///
  /// Respects the `platform_mode_override` in `shared_preferences`:
  /// - `editor` → force editor layout
  /// - `reader` → force reader layout
  /// - `auto` (or unset) → use `MediaQuery` heuristic: shortestSide >= 600
  static Future<bool> isEditorMode(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final override = prefs.getString('platform_mode_override');
    if (override == 'editor') return true;
    if (override == 'reader') return false;
    return MediaQuery.of(context).size.shortestSide >= 600;
  }

  /// Stores a persistent platform mode override.
  static Future<void> setModeOverride(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('platform_mode_override', mode);
  }

  /// Clears the stored override so the heuristic is used again.
  static Future<void> clearModeOverride() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('platform_mode_override');
  }
}
