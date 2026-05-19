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

    // ReaderLayout renders both NavigationRail (destinations) and
    // BottomNavigationBar simultaneously, so shared labels appear twice.
    expect(find.text('Home'), findsNWidgets(1));
    // "Lessons" and "Exams" appear in both NavigationRail and BottomNavigationBar
    expect(find.text('Lessons'), findsNWidgets(2));
    expect(find.text('Exams'), findsNWidgets(2));
    expect(find.text('More'), findsNWidgets(1));
    // "Dashboard" is a NavigationRail-only destination, absent from BottomNavBar
    expect(find.text('Dashboard'), findsNothing);
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

    // Both NavigationRail and BottomNavigationBar render "Lessons" and "Exams".
    expect(find.text('Home'), findsNWidgets(1));
    expect(find.text('Lessons'), findsNWidgets(2));
    expect(find.text('Exams'), findsNWidgets(2));
    expect(find.text('More'), findsNWidgets(1));
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
