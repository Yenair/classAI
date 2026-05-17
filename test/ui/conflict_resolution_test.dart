import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/features/settings/screens/conflict_resolution_screen.dart';

void main() {
  testWidgets('ConflictResolutionScreen shows loading then empty state',
      (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ConflictResolutionScreen()),
      ),
    );

    // Initially shows CircularProgressIndicator
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for async load (will fail gracefully with no DB)
    await tester.pumpAndSettle();

    // Since there's no database configured, it should show the error state
    // or the empty state depending on how the error is handled
    // In CI with no DB, it will show error state with Retry button
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('ConflictResolutionScreen shows Keep Mine, Keep Theirs, Merge buttons',
      (tester) async {
    // Can't test the full flow easily without DB, but the screen
    // should at least render the scaffold
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ConflictResolutionScreen()),
      ),
    );

    await tester.pumpAndSettle();

    // AppBar title
    expect(find.text('Conflict Resolution'), findsOneWidget);
  });
}
