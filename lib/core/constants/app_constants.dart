import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

class AppConstants {
  static const String appName = 'ClassAI';
  static const String deepLinkScheme = 'classai';
  static const int minTabletWidth = 600; // shortestSide for Editor mode
  static const int maxImageSizeKB = 50;
  static const int syncBatchSize = 10;
  static const int maxPushRetries = 5;
  static const Duration pushRetryBase = Duration(seconds: 5);
  static const Duration syncCooldown = Duration(seconds: 60);
  static const Duration sessionKeyTTL = Duration(minutes: 15);
  static const int biometricTimeoutSeconds = 10;

  /// Retrieves a real device identifier using [DeviceInfoPlugin].
  ///
  /// - **Android**: returns the Android ID ([AndroidDeviceInfo.id]).
  /// - **iOS**: returns the identifier for vendor
  ///   ([IosDeviceInfo.identifierForVendor]).
  /// - **Fallback** (e.g., tests, unsupported platforms): returns a random UUID.
  static Future<String> getDeviceId() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      if (defaultTargetPlatform == TargetPlatform.android) {
        final androidInfo = await deviceInfo.androidInfo;
        return androidInfo.id;
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        final iosInfo = await deviceInfo.iosInfo;
        return iosInfo.identifierForVendor ?? const Uuid().v4();
      }
    } catch (_) {
      // DeviceInfoPlugin may throw in test environments; fall through to UUID.
    }
    return const Uuid().v4();
  }
}
