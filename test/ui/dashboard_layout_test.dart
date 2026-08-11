import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/config_service.dart';
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

class MockSupabaseClient extends Mock implements SupabaseClient {}
class MockFunctionsClient extends Mock implements FunctionsClient {}

/// Builds a mock Supabase client whose `get-config` function fails fast so
/// [ConfigService.refresh] throws synchronously with no network I/O.
MockSupabaseClient buildMockSupabase() {
  final supabase = MockSupabaseClient();
  final functions = MockFunctionsClient();
  when(() => functions.invoke('get-config')).thenThrow(
    FunctionException(status: 500),
  );
  when(() => supabase.functions).thenReturn(functions);
  return supabase;
}

void main() {
  final mockSupabase = buildMockSupabase();
  testWidgets('EditorLayout shows nav drawer and header', (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configServiceProvider.overrideWithValue(
            ConfigService(client: mockSupabase),
          ),
        ],
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
    // (Vault is disabled and Scheme of Work is admin-only, so the drawer
    // has Home, Lessons, Exams only.)
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Lessons'), findsOneWidget);
    expect(find.text('Exams'), findsOneWidget);
    expect(find.text('Scheme of Work'), findsNothing);
  });

  testWidgets('EditorLayout has 3 nav items (non-admin)',
      (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });

    // pumpWidget with a fresh ProviderScope tree
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          configServiceProvider.overrideWithValue(
            ConfigService(client: mockSupabase),
          ),
        ],
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

    // A non-admin teacher gets exactly 3 nav items: Home, Lessons, Exams.
    // (Vault is disabled and Scheme of Work is admin-only.) The sidebar
    // header/logo is a separate InkWell, so we assert on the item labels
    // rather than an InkWell count.
    const navLabels = ['Home', 'Lessons', 'Exams'];
    for (final label in navLabels) {
      expect(
        find.descendant(of: sidebar.first, matching: find.text(label)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: sidebar.first, matching: find.text('Vault')),
      findsNothing,
    );
    expect(
      find.descendant(of: sidebar.first, matching: find.text('Scheme of Work')),
      findsNothing,
    );
    expect(
      find.descendant(of: sidebar.first, matching: find.text('Admin')),
      findsNothing,
    );

    // Admin icon should NOT be present for non-admin users
    expect(find.byIcon(Icons.admin_panel_settings_rounded), findsNothing);
  });
}
