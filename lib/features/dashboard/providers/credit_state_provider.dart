import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Data exposed to the daily credits counter widget.
class DailyCreditStateData {
  final int currentDailyCredits;
  final String tierName;
  final bool loading;
  final String? errorMessage;

  const DailyCreditStateData({
    this.currentDailyCredits = 0,
    this.tierName = 'Free',
    this.loading = false,
    this.errorMessage,
  });
}

/// Notifier that provides current daily credit state for UI display.
class DailyCreditStateNotifier extends Notifier<DailyCreditStateData> {
  @override
  DailyCreditStateData build() {
    return const DailyCreditStateData(loading: true);
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Refresh credit state from the database.
  Future<void> refresh() async {
    try {
      final config = await _db.securityConfigDao.get();
      String tierName = 'Free';
      try {
        final school = await _db.schoolsDao.get();
        final tier = school?.subscriptionTier ?? 'free';
        tierName = tier[0].toUpperCase() + tier.substring(1).toLowerCase();
      } catch (_) {
        tierName = 'Free';
      }
      state = DailyCreditStateData(
        currentDailyCredits: config.offlineCredits,
        tierName: tierName,
      );
    } catch (e) {
      state = DailyCreditStateData(
        errorMessage: 'Failed to load daily credits: $e',
      );
    }
  }
}

final dailyCreditStateProvider =
    NotifierProvider<DailyCreditStateNotifier, DailyCreditStateData>(
  DailyCreditStateNotifier.new,
);
