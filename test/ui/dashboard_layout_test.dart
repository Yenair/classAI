import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';

void main() {
  testWidgets('EditorLayout shows NavigationRail and AppBar', (tester) async {
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: EditorLayout()),
      ),
    );

    // Wait for async operations
    await tester.pumpAndSettle();

    // NavigationRail should be present
    expect(find.byType(NavigationRail), findsOneWidget);

    // AppBar should have ClassAI title
    expect(find.text('ClassAI'), findsWidgets);
  });

  testWidgets('EditorLayout has 5 rail destinations', (tester) async {
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });

    // pumpWidget with a fresh ProviderScope tree — this and the assertion
    // below act as the isolation guard; each WidgetTester is fresh per test.
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: EditorLayout()),
      ),
    );

    await tester.pumpAndSettle();

    // Verify there is exactly one EditorLayout — signals the tree is clean.
    expect(find.byType(EditorLayout).evaluate(), hasLength(1));

    // Each NavigationRail destination wraps its content in a GestureDetector.
    // Count GestureDetector descendants to verify exactly 5 destinations
    // without touching private SDK types or private fields.
    final rail = find.byType(NavigationRail);
    expect(rail, findsOneWidget);
    final gestureDetectors = find
        .descendant(of: rail, matching: find.byType(GestureDetector))
        .evaluate()
        .length;
    expect(gestureDetectors, equals(5));
  });
}
