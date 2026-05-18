import 'package:sentry_flutter/sentry_flutter.dart';

/// Centralized emergency save mechanism.
/// Replaces Riverpod onDispose for forced logout auto-save.
/// Every form provider REGISTERS its save callback at creation time.
/// On forced logout, this service calls all registered callbacks atomically.

typedef SaveCallback = Future<void> Function();

class EmergencyFlushService {
  final List<SaveCallback> _callbacks = [];

  void register(SaveCallback callback) {
    _callbacks.add(callback);
  }

  void unregister(SaveCallback callback) {
    _callbacks.remove(callback);
  }

  Future<void> flushAll() async {
    final results = <bool>[];
    for (final callback in List.from(_callbacks)) {
      try {
        await callback();
        results.add(true);
      } catch (e) {
        results.add(false);
        // Log failure but continue flushing others
        await Sentry.captureException(
          e,
          hint: null,
        );
      }
    }
    // If any failed, log to Sentry
    if (results.any((r) => !r)) {
      await Sentry.captureMessage('Emergency flush incomplete');
    }
    _callbacks.clear();
  }
}
