import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';

/// Increase the test viewport so the dashboard content does not
/// overflow the default 800×600 surface.  The dashboard's Row at line 425
/// needs extra width to fit its preview cards.
Future<void> ensureViewportHeight(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1200, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _wrapApp(Widget child) {
  return MaterialApp(
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(0.55),
      ),
      child: widget!,
    ),
    home: child,
  );
}

void main() {
  testWidgets('ReaderLayout shows bottom navigation with 4 items',
      (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: _wrapApp(const ReaderLayout()),
      ),
    );

    // Pump to render the frame (initState uses addPostFrameCallback which
    // triggers async providers that never settle in isolation).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Custom bottom nav renders Home, Lessons, Exams, More labels.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    // "Dashboard" is an EditorLayout-only destination
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('ReaderLayout shows Home, Lessons, Exams, More labels',
      (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: _wrapApp(const ReaderLayout()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
  });

  testWidgets('ReaderLayout shows ClassAI title in header',
      (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: _wrapApp(const ReaderLayout()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ClassAI'), findsWidgets);
  });
}
