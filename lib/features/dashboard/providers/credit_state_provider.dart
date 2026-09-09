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
  ///
  /// Reads the unified daily-credit pool (2F.2): the remaining balance for
  /// today (never negative, capped at the tier limit) — read-only, no spend.
  Future<void> refresh() async {
    try {
      String tierName = 'Free';
      String tier = 'free';
      try {
        final school = await _db.schoolsDao.get();
        tier = (school?.subscriptionTier ?? 'free').toLowerCase();
        tierName = tier[0].toUpperCase() + tier.substring(1).toLowerCase();
      } catch (_) {
        tierName = 'Free';
      }
      final remaining = await _db.securityConfigDao
          .getRemainingDailyCredits(tier: tier);
      // -1 = unlimited (elite); the chip renders it as ∞.
      state = DailyCreditStateData(
        currentDailyCredits: remaining,
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
