import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Provides a count of unresolved conflicts for the conflict banner widget.
///
/// Refreshes automatically when conflicts change (auto-dispose with ref.watch
/// in the widget). Also exposes a `refresh()` method for manual refresh.
class UnresolvedConflictsNotifier extends Notifier<int> {
  @override
  int build() {
    // Initialise to 0; widget should call refresh() after mount.
    return 0;
  }

  AppDatabase get _db => ref.read(databaseProvider);

  /// Queries the conflicts table for unresolved entries.
  Future<void> refresh() async {
    try {
      final conflicts = await (_db.select(_db.conflicts)
            ..where((t) => t.resolution.equals('unresolved')))
          .get();
      state = conflicts.length;
    } catch (_) {
      state = 0;
    }
  }
}

final unresolvedConflictsProvider =
    NotifierProvider<UnresolvedConflictsNotifier, int>(
  UnresolvedConflictsNotifier.new,
);
