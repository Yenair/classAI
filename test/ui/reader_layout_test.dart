import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';
import 'package:classai/core/database/database.dart';
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

class TestCreditStateNotifier extends CreditStateNotifier {
  @override
  CreditStateData build() => const CreditStateData();
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

void main() {
  final testDb = AppDatabase.forTesting();

  testWidgets('ReaderLayout shows bottom navigation with 5 items',
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
          creditStateProvider.overrideWith(
            () => TestCreditStateNotifier(),
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

    expect(bottomNavItems, findsNWidgets(5));

    // Custom bottom nav renders Home, Lessons, Exams, Scheme of Work, More.
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
      findsOneWidget,
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

  testWidgets('ReaderLayout shows Home, Lessons, Exams, Scheme of Work, More labels',
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
          creditStateProvider.overrideWith(
            () => TestCreditStateNotifier(),
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

    expect(bottomNavItems, findsNWidgets(5));
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
      findsOneWidget,
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
          creditStateProvider.overrideWith(
            () => TestCreditStateNotifier(),
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
