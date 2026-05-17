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

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: EditorLayout()),
      ),
    );

    await tester.pumpAndSettle();

    // Should find 5 destination labels
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });
}
