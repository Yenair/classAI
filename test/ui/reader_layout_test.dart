import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/providers/sync_status_provider.dart';
import 'package:classai/features/dashboard/providers/credit_state_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

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

class TestAuthNotifier extends AuthNotifier {
  @override
  AuthStateData build() => const AuthStateData(
        state: AuthState.authenticated,
      );
}

class TestDailyCreditStateNotifier extends DailyCreditStateNotifier {
  @override
  DailyCreditStateData build() => const DailyCreditStateData();
}

class TestSyncStatusNotifier extends SyncStatusNotifier {
  final SyncStatusData fixedData;

  TestSyncStatusNotifier(this.fixedData);

  @override
  SyncStatusData build() => fixedData;

  @override
  Future<void> refresh() async {}

  @override
  Future<void> syncNow() async {}
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
  final testDb = AppDatabase.forTesting();
  final mockSupabase = buildMockSupabase();

  testWidgets('ReaderLayout shows bottom navigation with 4 items',
      (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(testDb),
          authProvider.overrideWith(() => TestAuthNotifier()),
          syncStatusProvider.overrideWith(() => TestSyncStatusNotifier(
                const SyncStatusData(status: SyncStatus.synced),
              )),
          dailyCreditStateProvider.overrideWith(
            () => TestDailyCreditStateNotifier(),
          ),
          configServiceProvider.overrideWithValue(
            ConfigService(client: mockSupabase),
          ),
        ],
        child: _wrapApp(const ReaderLayout()),
      ),
    );

    // Pump to render the frame (initState uses addPostFrameCallback which
    // triggers async providers that never settle in isolation).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final bottomNavItems = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_BottomNavItem',
    );

    expect(bottomNavItems, findsNWidgets(4));

    // Custom bottom nav renders Home, Lessons, Exams, More for a non-admin.
    // (Scheme of Work is admin-only and hidden for teachers.)
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Lessons'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Exams'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Scheme of Work'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('More'),
      ),
      findsOneWidget,
    );
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
        overrides: [
          databaseProvider.overrideWithValue(testDb),
          authProvider.overrideWith(() => TestAuthNotifier()),
          syncStatusProvider.overrideWith(() => TestSyncStatusNotifier(
                const SyncStatusData(status: SyncStatus.synced),
              )),
          dailyCreditStateProvider.overrideWith(
            () => TestDailyCreditStateNotifier(),
          ),
          configServiceProvider.overrideWithValue(
            ConfigService(client: mockSupabase),
          ),
        ],
        child: _wrapApp(const ReaderLayout()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final bottomNavItems = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_BottomNavItem',
    );

    expect(bottomNavItems, findsNWidgets(4));
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Home'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Lessons'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Exams'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('Scheme of Work'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: bottomNavItems,
        matching: find.text('More'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('ReaderLayout shows ClassAI title in header',
      (tester) async {
    await ensureViewportHeight(tester);
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(testDb),
          authProvider.overrideWith(() => TestAuthNotifier()),
          syncStatusProvider.overrideWith(() => TestSyncStatusNotifier(
                const SyncStatusData(status: SyncStatus.synced),
              )),
          dailyCreditStateProvider.overrideWith(
            () => TestDailyCreditStateNotifier(),
          ),
          configServiceProvider.overrideWithValue(
            ConfigService(client: mockSupabase),
          ),
        ],
        child: _wrapApp(const ReaderLayout()),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('ClassAI'), findsWidgets);
  });
}
