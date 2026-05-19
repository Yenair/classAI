import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/widgets/conflict_banner.dart';
import 'package:classai/features/dashboard/providers/unresolved_conflicts_provider.dart';

/// Test notifier extending UnresolvedConflictsNotifier with fixed count.
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

Widget _buildApp(int conflictCount) {
  return ProviderScope(
    overrides: [
      unresolvedConflictsProvider.overrideWith(
        () => TestUnresolvedConflictsNotifier(conflictCount),
      ),
    ],
    child: const MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            ConflictBanner(),
            Expanded(child: Center(child: Text('Content'))),
          ],
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('ConflictBanner is hidden when no conflicts', (tester) async {
    await tester.pumpWidget(_buildApp(0));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialBanner), findsNothing);
  });

  testWidgets('ConflictBanner shows when conflicts exist', (tester) async {
    await tester.pumpWidget(_buildApp(3));
    await tester.pumpAndSettle();

    expect(find.byType(Container), findsOneWidget);
    expect(find.text('3 unresolved conflicts'), findsOneWidget);
  });

  testWidgets('ConflictBanner shows singular text for 1 conflict',
      (tester) async {
    await tester.pumpWidget(_buildApp(1));
    await tester.pumpAndSettle();

    expect(find.text('1 unresolved conflict'), findsOneWidget);
  });

  testWidgets('ConflictBanner has REVIEW button', (tester) async {
    await tester.pumpWidget(_buildApp(2));
    await tester.pumpAndSettle();

    expect(find.text('REVIEW'), findsOneWidget);
    expect(find.byType(TextButton), findsOneWidget);
  });

  testWidgets('ConflictBanner shows warning icon', (tester) async {
    await tester.pumpWidget(_buildApp(1));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
  });
}
