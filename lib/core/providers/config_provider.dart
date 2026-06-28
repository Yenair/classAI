// lib/core/providers/config_provider.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/services/config_service.dart';

/// Provider that holds a singleton [ConfigService] instance.
/// The service is refreshed once on first access.
final configServiceProvider = Provider<ConfigService>((ref) {
  final service = ConfigService();
  // Fire-and-forget initial fetch
  service.refresh();
  return service;
});
