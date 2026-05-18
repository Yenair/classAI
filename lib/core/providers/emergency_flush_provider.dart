import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/services/emergency_flush_service.dart';

/// Shared singleton provider for [EmergencyFlushService].
///
/// Both [AuthNotifier] and form editors (lesson, exam, etc.) must read from
/// the **same** provider instance so that callbacks registered by editors are
/// flushed when [EmergencyFlushService.flushAll] is called during a forced
/// logout. Having duplicate definitions (as was the case before) caused the
/// lesson editor's callback to be registered on a different singleton than
/// the one used by [AuthNotifier], leading to data loss.
final emergencyFlushServiceProvider = Provider<EmergencyFlushService>((ref) {
  return EmergencyFlushService();
});
