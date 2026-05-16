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
}
