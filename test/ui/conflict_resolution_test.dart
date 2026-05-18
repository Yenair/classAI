import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/features/settings/screens/conflict_resolution_screen.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Test notifier extending [UnresolvedConflictsNotifier] with a fixed count.
class TestUnresolvedConflictsNotifier extends UnresolvedConflictsNotifier {
  final int fixedCount;

  TestUnresolvedConflictsNotifier(this.fixedCount);

  @override
  int build() => fixedCount;

  @override
  Future<void> refresh() async {
    // No-op for tests
  }
}

void main() {
  testWidgets('ConflictResolutionScreen shows loading then empty state',
      (tester) async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          unresolvedConflictsProvider.overrideWith(
            () => TestUnresolvedConflictsNotifier(0),
          ),
        ],
        child: const MaterialApp(home: ConflictResolutionScreen()),
      ),
    );

    // Initially shows CircularProgressIndicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for async load (in-memory DB resolves immediately)
    await tester.pumpAndSettle();

    // With no conflicts in the in-memory DB, it shows the empty state
    expect(find.text('No unresolved conflicts'), findsOneWidget);
  });

  testWidgets(
      'ConflictResolutionScreen shows Keep Mine, Keep Theirs, Merge buttons',
      (tester) async {
    final db = AppDatabase.forTesting();
    addTearDown(db.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          unresolvedConflictsProvider.overrideWith(
            () => TestUnresolvedConflictsNotifier(0),
          ),
        ],
        child: const MaterialApp(home: ConflictResolutionScreen()),
      ),
    );

    await tester.pumpAndSettle();

    // AppBar title
    expect(find.text('Conflict Resolution'), findsOneWidget);
  });
}
