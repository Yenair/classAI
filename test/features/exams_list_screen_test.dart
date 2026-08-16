import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/exam/screens/exams_list_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:classai/router/app_router.dart' show appRouter;
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide AuthState;

/// A connectivity platform stub so `PlatformHelper.isOnline()` is
/// deterministic in the widget tests.
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async =>
      [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

class FixedAuthNotifier extends AuthNotifier {
  FixedAuthNotifier(this.fixedState);

  final AuthStateData fixedState;

  @override
  AuthStateData build() => fixedState;
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

class _AuthFixture {
  _AuthFixture({
    required this.schoolId,
    required this.teacherId,
    required this.school,
    required this.teacher,
  });

  final int schoolId;
  final int teacherId;
  final School school;
  final Teacher teacher;
}

Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
        SecurityConfigCompanion.insert(
          currentDeviceId: 'exams-list-test-device',
          lastRealtimeEventId: Value(0),
        ),
      );
}

Future<_AuthFixture> _seedAuth(AppDatabase db) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000a01'),
          schoolName: 'Test School',
          shortCode: 'TSA01',
          subscriptionTier: const Value('free'),
        ),
      );
  final teacherId = await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000a02'),
          email: 'teacher@testschool.local',
          teacherName: 'Test Teacher',
          role: Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000a01'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );
  final school = await db.schoolsDao.getByLocalId(schoolId);
  final teacher = await db.teachersDao.getById(teacherId);
  if (school == null || teacher == null) {
    throw StateError('Failed to seed auth fixture');
  }
  return _AuthFixture(
    schoolId: schoolId,
    teacherId: teacherId,
    school: school,
    teacher: teacher,
  );
}

/// Seeds one saved scheme week for Mathematics / JSS 1 / 1st Term — the
/// exact setup that used to make the Exams list silently seed a draft exam.
Future<void> _seedScheme(AppDatabase db, _AuthFixture fixture) async {
  final subjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-000000000a03',
    name: 'Mathematics',
    schoolId: '00000000-0000-0000-0000-000000000a01',
    sortOrder: 1,
  );
  await db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          schoolId: Value(fixture.schoolId),
          teacherId: Value(fixture.teacherId),
          subjectId: Value(subjectId),
          term: const Value('First'),
          weekNumber: const Value(1),
          topic: const Value('Algebraic Expressions'),
          objectives: const Value('Understand variables'),
          status: const Value('draft'),
          classLevel: const Value('JSS 1'),
        ),
      );
}

AuthStateData _authState(_AuthFixture fixture) {
  return AuthStateData(
    state: AuthState.authenticated,
    currentTeacher: fixture.teacher,
    currentSchool: fixture.school,
  );
}

/// Seeds one CA Test exam and one weekly exam so the type tabs and badges
/// can be exercised.
Future<void> _seedExams(AppDatabase db, _AuthFixture fixture) async {
  await db.examsDao.insertExam(
    ExamsCompanion.insert(
      subject: 'Mathematics',
      classLevel: 'JSS 1',
      topic: 'CA Test (2 topics)',
      difficulty: 'medium',
      curriculum: 'NERDC',
      content: '{"mcqs":[],"theory":[],"subjective":[]}',
      teacherServerId: Value(fixture.teacher.serverId),
      schoolServerId: Value(fixture.school.serverId),
      isUnlocked: const Value(false),
      weekNumber: const Value(2),
      term: const Value('1st Term'),
    ),
  );
  await db.examsDao.insertExam(
    ExamsCompanion.insert(
      subject: 'Mathematics',
      classLevel: 'JSS 1',
      topic: 'Algebraic Expressions',
      difficulty: 'medium',
      curriculum: 'NERDC',
      content: '{"mcqs":[],"theory":[],"subjective":[]}',
      teacherServerId: Value(fixture.teacher.serverId),
      schoolServerId: Value(fixture.school.serverId),
      isUnlocked: const Value(false),
      weekNumber: const Value(1),
      term: const Value('1st Term'),
      schemeOfWorkId: const Value('99'),
    ),
  );
}

/// Pumps the full router app (MaterialApp.router with [appRouter]) so route
/// navigation from the choice screen can be exercised.
Future<void> _pumpRouterApp(
  WidgetTester tester, {
  required AppDatabase db,
  required _AuthFixture fixture,
}) async {
  tester.view.physicalSize = const Size(1600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(_authState(fixture)),
        ),
        configServiceProvider.overrideWithValue(
          ConfigService(client: buildMockSupabase()),
        ),
      ],
      child: MaterialApp.router(routerConfig: appRouter),
    ),
  );
  // Explicit pumps — the dashboard's async providers never fully settle
  // in isolation, so pumpAndSettle would time out.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _pumpExamsList(
  WidgetTester tester, {
  required AppDatabase db,
  required _AuthFixture fixture,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(_authState(fixture)),
        ),
      ],
      child: const MaterialApp(home: ExamsListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _AuthFixture fixture;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    await _seedConfig(db);
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();
    SharedPreferences.setMockInitialValues({});
    fixture = await _seedAuth(db);
  });

  tearDown(() async {
    ConnectivityPlatform.instance = MethodChannelConnectivity();
    await db.close();
  });

  testWidgets(
    'opening the Exams list no longer seeds draft exams from saved schemes',
    (tester) async {
      await _seedScheme(db, fixture);

      await _pumpExamsList(tester, db: db, fixture: fixture);

      // The saved scheme is present, but NOTHING is bootstrapped from it.
      expect(await db.examsDao.getAll(), isEmpty,
          reason: 'the Exams list must never silently create exams');
      final queue = await db.syncQueueDao.pendingEntries();
      expect(queue.where((e) => e.queueTable == 'exams'), isEmpty,
          reason: 'no exam creation may be queued by opening the list');

      // The zero state repeats the /exams creation cards: the two primary
      // cards plus the Weekly Exams disclosure link.
      expect(find.text('No exams yet'), findsOneWidget);
      expect(find.text('Term Exam'), findsOneWidget);
      expect(find.text('CA Test (Class Test)'), findsOneWidget);
      expect(find.text('More ways to make a test ▾'), findsOneWidget);
      expect(find.text('Weekly Exams').hitTestable(), findsNothing,
          reason: 'Weekly Exams is hidden behind the disclosure link');
      expect(find.text('New Exam'), findsNothing,
          reason: 'the old single-exam FAB is gone');
    },
  );

  testWidgets(
    'the Exams list shows both creation actions even when empty',
    (tester) async {
      await _pumpExamsList(tester, db: db, fixture: fixture);

      expect(await db.examsDao.getAll(), isEmpty);
      expect(find.text('No exams yet'), findsOneWidget);
      expect(find.text('Term Exam'), findsOneWidget);
      expect(find.text('CA Test (Class Test)'), findsOneWidget);
      expect(find.text('More ways to make a test ▾'), findsOneWidget);
      expect(find.text('Weekly Exams').hitTestable(), findsNothing,
          reason: 'Weekly Exams is hidden behind the disclosure link');
    },
  );

  test('the standalone /full-term-exam route is removed from the router', () {
    final paths = appRouter.configuration.routes
        .whereType<GoRoute>()
        .map((r) => r.path)
        .toList();
    expect(paths, isNot(contains('/full-term-exam')),
        reason: 'the old Full-Term Exam screen must not be a route anymore');
    expect(paths, contains('/exam-editor'));
    expect(paths, contains('/exams/list'),
        reason: 'the list-only screen must be reachable at /exams/list');
    expect(paths, contains('/weekly-exams-setup'),
        reason: 'Weekly Exams setup must be a route');
  });

  testWidgets('/full-term-exam redirects to the exam editor in Term Exam mode',
      (tester) async {
    // Pump at a wide viewport so the Dashboard (pumped on app start) does
    // not overflow in the default narrow test window.
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWithValue(db),
          authProvider.overrideWith(
            () => FixedAuthNotifier(_authState(fixture)),
          ),
          configServiceProvider.overrideWithValue(
            ConfigService(client: buildMockSupabase()),
          ),
        ],
        child: MaterialApp.router(routerConfig: appRouter),
      ),
    );
    // Explicit pumps — the dashboard's async providers never fully settle
    // in isolation, so pumpAndSettle would time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    appRouter.go('/full-term-exam');
    // Drive the redirect, the exam editor build and its topic loading.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final uri = appRouter.routeInformationProvider.value.uri;
    expect(uri.path, '/exam-editor',
        reason: '/full-term-exam must land in the exam editor');
    expect(uri.queryParameters['compilationType'], 'termExam',
        reason: 'the redirected editor must open in Term Exam mode');
  });

  testWidgets('the /exams choice screen shows primary cards, disclosure, '
      'and View my exams', (tester) async {
    await _pumpRouterApp(tester, db: db, fixture: fixture);
    appRouter.go('/exams');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('What do you want to make?'), findsOneWidget);
    expect(find.text('Term Exam'), findsOneWidget);
    expect(find.text('CA Test (Class Test)'), findsOneWidget);
    expect(find.text('More ways to make a test ▾'), findsOneWidget);
    expect(find.text('View my exams'), findsOneWidget);
    // Weekly Exams is hidden until the disclosure link is expanded. The card
    // stays in the tree inside AnimatedCrossFade, so visibility is asserted
    // via hit-testability (invisible children ignore pointers).
    expect(find.text('Weekly Exams').hitTestable(), findsNothing);

    // Expanding the disclosure reveals the Weekly Exams card inline.
    await tester.tap(find.text('More ways to make a test ▾'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly Exams').hitTestable(), findsOneWidget);
    expect(find.text('More ways to make a test ▴'), findsOneWidget);

    // The disclosure stays on screen and can be toggled back.
    await tester.tap(find.text('More ways to make a test ▴'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly Exams').hitTestable(), findsNothing);
  });

  testWidgets('View my exams on the choice screen routes to /exams/list',
      (tester) async {
    await _pumpRouterApp(tester, db: db, fixture: fixture);
    appRouter.go('/exams');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    await tester.tap(find.text('View my exams'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The button uses `push`, which go_router treats as an imperative
    // navigation: `routeInformationProvider.value.uri` deliberately stays at
    // the base location ('/exams') unless `optionURLReflectsImperativeAPIs`
    // is enabled. The pushed page's own state is the source of truth, so
    // assert against the route state of the ExamsListScreen that got pushed.
    final pushedState = GoRouterState.of(
      tester.element(find.byType(ExamsListScreen)),
    );
    expect(pushedState.uri.path, '/exams/list',
        reason: 'View my exams must open the list-only screen');
    expect(find.text('No exams yet'), findsOneWidget);
  });

  testWidgets('the list shows type tabs and badges, and tabs filter the list',
      (tester) async {
    await _seedExams(db, fixture);
    await _pumpExamsList(tester, db: db, fixture: fixture);

    // All four tabs are visible; the active tab is 'All'. ('All' is scoped
    // to the tabs row because the status filter chips also contain 'All'.)
    final tabsRow = find.byType(SingleChildScrollView).first;
    Finder typeTab(String label) =>
        find.descendant(of: tabsRow, matching: find.text(label));

    expect(typeTab('All'), findsOneWidget);
    expect(typeTab('CA Test (Class Test)'), findsOneWidget);
    expect(typeTab('Term Exam'), findsOneWidget);
    // 'Weekly Exams' appears twice: the tab plus the weekly exam's badge.
    expect(find.text('Weekly Exams'), findsNWidgets(2));
    // The CA exam card shows its badge regardless of the active tab.
    expect(find.text('CA Test'), findsOneWidget);

    // Tapping the CA Test tab filters to only the CA exam.
    await tester.tap(typeTab('CA Test (Class Test)'));
    await tester.pumpAndSettle();
    expect(find.text('CA Test'), findsOneWidget);
    expect(find.text('Weekly Exams'), findsOneWidget,
        reason: 'only the tab remains — the weekly exam card is filtered out');

    // Back to All restores both cards.
    await tester.tap(typeTab('All'));
    await tester.pumpAndSettle();
    expect(find.text('Weekly Exams'), findsNWidgets(2));
  });

  testWidgets('deleting an exam offers Undo and restores the row',
      (tester) async {
    await _seedExams(db, fixture);
    await _pumpExamsList(tester, db: db, fixture: fixture);

    expect(find.byTooltip('Delete'), findsNWidgets(2));
    await tester.tap(find.byTooltip('Delete').first);
    await tester.pumpAndSettle();
    expect(find.text('Delete Exam'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();

    expect(find.text('Exam deleted'), findsOneWidget);
    expect(find.text('Undo'), findsOneWidget);
    expect((await db.examsDao.getAll()).length, 1,
        reason: 'one exam is soft-deleted');

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect((await db.examsDao.getAll()).length, 2,
        reason: 'Undo restores the deleted exam');
  });
}
