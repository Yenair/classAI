import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Data exposed to the credit counter widget.
class CreditStateData {
  final int currentCredits;
  final String tierName;
  final bool loading;
  final String? errorMessage;

  const CreditStateData({
    this.currentCredits = 0,
    this.tierName = 'Free',
    this.loading = false,
    this.errorMessage,
  });
}

/// Notifier that provides current credit state for UI display.
class CreditStateNotifier extends Notifier<CreditStateData> {
  @override
  CreditStateData build() {
    return const CreditStateData(loading: true);
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Refresh credit state from the database.
  Future<void> refresh() async {
    try {
      final config = await _db.securityConfigDao.get();
      state = CreditStateData(
        currentCredits: config.offlineCredits,
        tierName: _tierFromCredits(config.offlineCredits),
      );
    } catch (e) {
      state = CreditStateData(
        errorMessage: 'Failed to load credits: $e',
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

final creditStateProvider =
    NotifierProvider<CreditStateNotifier, CreditStateData>(
  CreditStateNotifier.new,
);
