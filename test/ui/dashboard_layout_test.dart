import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';

/// Increase the test viewport so the dashboard content does not
/// overflow the default 800×600 surface.  The editor-layout nav-drawer
/// Row (dashboard_screen.dart:149) needs extra width to fit the logo +
/// "ClassAI" title + "Nigerian Academic Partner" subtitle.
Future<void> ensureViewportHeight(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

Widget _wrapApp(Widget child) {
  return MaterialApp(
    builder: (context, widget) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: const TextScaler.linear(0.4),
      ),
      child: widget!,
    ),
    home: child,
  );
}

void main() {
  testWidgets('EditorLayout shows nav drawer and header', (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });

    await tester.pumpWidget(
      ProviderScope(
        child: _wrapApp(const EditorLayout()),
      ),
    );

    // Pump to render the frame (initState uses addPostFrameCallback which
    // triggers async providers that never settle in isolation).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Header should have ClassAI title
    expect(find.text('ClassAI'), findsWidgets);

    // Nav drawer labels should be present for a non-admin teacher.
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('Vault'), findsOneWidget);
    expect(find.text('Scheme of Work'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('EditorLayout has 5 nav icons (non-admin)',
      (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });

    // pumpWidget with a fresh ProviderScope tree
    await tester.pumpWidget(
      ProviderScope(
        child: _wrapApp(const EditorLayout()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // Verify there is exactly one EditorLayout
    expect(find.byType(EditorLayout).evaluate(), hasLength(1));

    // The sidebar is a custom Column in the left AnimatedContainer.
    // Scope the search to the sidebar using its unique "ClassAI" header.
    final sidebar = find.ancestor(
      of: find.text('ClassAI'),
      matching: find.byType(AnimatedContainer),
    );
    expect(sidebar, findsWidgets);

    final sidebarNavItems = find.descendant(
      of: sidebar.first,
      matching: find.byType(InkWell),
    );
    expect(sidebarNavItems, findsNWidgets(5));

    // Admin icon should NOT be present for non-admin users
    expect(find.byIcon(Icons.admin_panel_settings_rounded), findsNothing);
  });
}
