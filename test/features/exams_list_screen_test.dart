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

      // The two explicit creation actions are visible.
      expect(find.text('Generate Weekly Exams'), findsOneWidget);
      expect(find.text('Term Exam / CA Test'), findsOneWidget);
      expect(find.text('New Exam'), findsNothing,
          reason: 'the old single-exam FAB is gone');
    },
  );

  testWidgets(
    'the Exams list shows both creation actions even when empty',
    (tester) async {
      await _pumpExamsList(tester, db: db, fixture: fixture);

      expect(await db.examsDao.getAll(), isEmpty);
      expect(find.text('Generate Weekly Exams'), findsOneWidget);
      expect(find.text('Term Exam / CA Test'), findsOneWidget);
      expect(find.text('No exams yet'), findsOneWidget);
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
}
