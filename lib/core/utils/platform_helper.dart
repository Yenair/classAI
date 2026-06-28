import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PlatformHelper {
  /// Returns `true` when the current platform can safely use the
  /// connectivity_plus realtime stream.
  static bool supportsConnectivityStream() {
    return true;
  }

  /// Returns `true` if the device has network connectivity.
  ///
  /// Uses [connectivity_plus] to confirm there is a transport available.
  /// This is a simple transport-level check with no side effects.
  /// For a stricter check that also probes DNS, use [isReliablyOnline].
  static Future<bool> isOnline() async {
    final connectivity = Connectivity();
    try {
      final results = await connectivity.checkConnectivity();
      return results.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }

  /// A stricter online check that performs a DNS lookup in addition to
  /// the transport check. Use this only where strict connectivity is
  /// required (e.g. subscription expiry checks), not in the general sync
  /// flow.
  static Future<bool> isReliablyOnline() async {
    if (!await isOnline()) return false;

    try {
      final lookup = await InternetAddress.lookup('example.com');
      return lookup.isNotEmpty &&
          lookup.any((address) => address.rawAddress.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

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
