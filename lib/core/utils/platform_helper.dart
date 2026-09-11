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

  /// Test seam: when non-null, [isOnline] (and therefore
  /// [isReliablyOnline]) returns this value without touching the
  /// connectivity plugin or DNS. Always null in production — only tests
  /// set it (see test/credits/credit_service_test.dart), and they reset
  /// it in tearDown.
  static bool? _isOnlineOverride;
  static set isOnlineOverride(bool? value) => _isOnlineOverride = value;

  /// Returns `true` if the device has network connectivity.
  ///
  /// First tries [connectivity_plus] for a transport-level check.  If that
  /// returns [ConnectivityResult.none] or throws (a known issue on some
  /// Android versions — PlatformException(0, NetworkManager::StartListen)),
  /// falls back to a DNS lookup of `example.com` as a reliable probe.
  ///
  /// For an even stricter check, use [isReliablyOnline].
  static Future<bool> isOnline() async {
    final override = _isOnlineOverride;
    if (override != null) return override;

    final connectivity = Connectivity();
    try {
      final results = await connectivity.checkConnectivity();
      if (results.any((r) => r != ConnectivityResult.none)) {
        return true;
      }
    } catch (_) {
      // connectivity_plus failed — fall through to DNS check below.
    }

    // Fallback: DNS lookup to confirm actual connectivity.
    try {
      final lookup = await InternetAddress.lookup('example.com');
      return lookup.isNotEmpty &&
          lookup.any((address) => address.rawAddress.isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  /// A stricter online check that performs a DNS lookup in addition to
  /// the transport check. Use this only where strict connectivity is
  /// required (e.g. subscription expiry checks), not in the general sync
  /// flow.
  static Future<bool> isReliablyOnline() async {
    final override = _isOnlineOverride;
    if (override != null) return override;

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

  /// Whether a screen should render the desktop sidebar.
  /// Returns `false` on Android (always bottom-nav) and on narrow (<768) viewports.
  static bool shouldShowSidebar(BuildContext context, {int minWidth = 768}) =>
      !Platform.isAndroid &&
      MediaQuery.of(context).size.width >= minWidth;
}
