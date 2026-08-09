import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Data exposed to the offline credit counter widget.
class OfflineCreditStateData {
  final int currentOfflineCredits;
  final String tierName;
  final bool loading;
  final String? errorMessage;

  const OfflineCreditStateData({
    this.currentOfflineCredits = 0,
    this.tierName = 'Free',
    this.loading = false,
    this.errorMessage,
  });
}

/// Notifier that provides current offline credit state for UI display.
class OfflineCreditStateNotifier extends Notifier<OfflineCreditStateData> {
  @override
  OfflineCreditStateData build() {
    return const OfflineCreditStateData(loading: true);
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Refresh credit state from the database.
  Future<void> refresh() async {
    try {
      final config = await _db.securityConfigDao.get();
      state = OfflineCreditStateData(
        currentOfflineCredits: config.offlineCredits,
        tierName: _tierFromCredits(config.offlineCredits),
      );
    } catch (e) {
      state = OfflineCreditStateData(
        errorMessage: 'Failed to load offline credits: $e',
      );
    }
  }

  String _tierFromCredits(int credits) {
    if (credits >= 100) return 'Premium';
    if (credits >= 50) return 'Pro';
    if (credits >= 10) return 'Standard';
    return 'Free';
  }
}

final offlineCreditStateProvider =
    NotifierProvider<OfflineCreditStateNotifier, OfflineCreditStateData>(
  OfflineCreditStateNotifier.new,
);
