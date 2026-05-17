import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';

void main() {
  testWidgets('ReaderLayout shows BottomNavigationBar with 4 items',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ReaderLayout()),
      ),
    );

    await tester.pumpAndSettle();

    // BottomNavigationBar should be present
    expect(find.byType(BottomNavigationBar), findsOneWidget);

    // Should have 4 items (check via labels)
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('ReaderLayout shows Home, Lessons, Exams, More labels',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ReaderLayout()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('ReaderLayout has AppBar with ClassAI title', (tester) async {
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: ReaderLayout()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('ClassAI'), findsWidgets);
  });
}
