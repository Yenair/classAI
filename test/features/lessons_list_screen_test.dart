import 'package:classai/core/database/database.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/lesson/screens/lessons_list_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart';
import 'package:drift/drift.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A connectivity platform stub so `PlatformHelper.isOnline()` is
/// deterministic in the widget tests. With a non-none result the online
/// check short-circuits to `true` without touching the DNS fallback.
class _FakeConnectivityPlatform extends ConnectivityPlatform {
  final List<ConnectivityResult> results;
  _FakeConnectivityPlatform(this.results);

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => results;

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

class AuthFixture {
  AuthFixture({required this.school, required this.teacher});

  final School school;
  final Teacher teacher;
}

/// Seeds the security config row so the sync/credit providers refresh cleanly.
Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
    SecurityConfigCompanion.insert(
      currentDeviceId: 'widget-test-device',
      lastRealtimeEventId: Value(0),
    ),
  );
}

/// Seeds school + teacher (no plan).
Future<AuthFixture> _seedAuthFixture(
  AppDatabase db, {
  required String teacherRole,
}) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000801'),
          schoolName: 'Test School',
          shortCode: 'TS801',
          subscriptionTier: const Value('free'),
        ),
      );

  final teacherId = await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000901'),
          email: 'teacher@testschool.local',
          teacherName: 'Test Teacher',
          role: Value(teacherRole),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000801'),
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
  return AuthFixture(school: school, teacher: teacher);
}

/// Seeds a plan (subject + one scheme_of_work week) for Mathematics / JSS 1
/// / 1st Term so the Plan My Term button flips to "Refresh Plan".
Future<void> _seedPlanFixture(AppDatabase db, AuthFixture fixture) async {
  final subjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-000000000a01',
    name: 'Mathematics',
    schoolId: '00000000-0000-0000-0000-000000000801',
    sortOrder: 1,
  );

  await db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          schoolId: Value(fixture.school.localId),
          teacherId: Value(fixture.teacher.localId),
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

AuthStateData _authState(AuthFixture fixture) {
  return AuthStateData(
    state: AuthState.authenticated,
    currentTeacher: fixture.teacher,
    currentSchool: fixture.school,
  );
}

Future<void> _pumpLessonsList(
  WidgetTester tester, {
  required AppDatabase db,
  required AuthFixture fixture,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(() => FixedAuthNotifier(_authState(fixture))),
      ],
      child: const MaterialApp(home: LessonsListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// The term filter dropdown on the lessons list filter panel.
Finder _termFilterDropdown() {
  return find.ancestor(
    of: find.text('Term'),
    matching: find.byType(DropdownButtonFormField<String>),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late AuthFixture fixture;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    await _seedConfig(db);
    ConnectivityPlatform.instance =
        _FakeConnectivityPlatform([ConnectivityResult.wifi]);
    SharedPreferences.setMockInitialValues({
      'lessons_filter_subject': 'Mathematics',
      'lessons_filter_class': 'JSS 1',
      'lessons_filter_term': '1st Term',
    });
  });

  tearDown(() async {
    ConnectivityPlatform.instance = MethodChannelConnectivity();
    await db.close();
  });

  group('LessonsListScreen Plan My Term button', () {
    testWidgets(
      'shows "Refresh Plan" with the refresh icon when a plan exists '
      'for the selected filters',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await _seedPlanFixture(db, fixture);

        await _pumpLessonsList(tester, db: db, fixture: fixture);

        expect(find.text('Refresh Plan'), findsOneWidget);
        expect(find.byIcon(Icons.refresh_rounded), findsWidgets);
        expect(find.text('Plan My Term'), findsNothing);
      },
    );

    testWidgets(
      'reverts to "Plan My Term" when the filter combo has no plan',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await _seedPlanFixture(db, fixture);

        await _pumpLessonsList(tester, db: db, fixture: fixture);
        expect(find.text('Refresh Plan'), findsOneWidget);

        // Change the term filter to one with no plan (2nd Term).
        await tester.tap(_termFilterDropdown());
        await tester.pumpAndSettle();
        await tester.tap(find.text('2nd Term').last);
        await tester.pumpAndSettle();

        expect(find.text('Plan My Term'), findsOneWidget);
        expect(find.text('Refresh Plan'), findsNothing);
        expect(find.byIcon(Icons.auto_awesome_rounded), findsWidgets);
      },
    );

    testWidgets(
      'refresh flow shows the confirmation dialog and cancelling keeps '
      'the plan intact',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await _seedPlanFixture(db, fixture);

        await _pumpLessonsList(tester, db: db, fixture: fixture);

        // Open the choice dialog in refresh mode.
        await tester.tap(find.text('Refresh Plan'));
        await tester.pumpAndSettle();
        expect(find.text('Use Built-in Topics'), findsOneWidget);
        expect(find.text('Get New Topics Online'), findsOneWidget);
        expect(find.text('Refresh your plan?'), findsNothing);

        // Pick "Use Built-in Topics" → confirmation dialog with warning copy.
        await tester.tap(find.text('Use Built-in Topics'));
        await tester.pumpAndSettle();
        expect(find.text('Refresh your plan?'), findsOneWidget);
        expect(
          find.textContaining(
            'This will replace your existing plan for Mathematics, '
            'JSS 1, 1st Term with fresh topics',
          ),
          findsOneWidget,
        );
        expect(
          find.textContaining(
            'Your previously generated lesson content will be kept, '
            'but topic titles may change',
          ),
          findsOneWidget,
        );

        // Cancel → confirmation closes, the plan is untouched. (The choice
        // dialog was popped when a button was tapped, so nothing remains.)
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('This will replace your existing plan'),
          findsNothing,
        );
        expect(find.byType(AlertDialog), findsNothing);
        final schemeRows = await (db.select(db.schemeOfWork)).get();
        expect(schemeRows, hasLength(1));
        expect(schemeRows.single.topic, 'Algebraic Expressions');
        expect(await db.syncQueueDao.pendingEntries(), isEmpty);
      },
    );

    testWidgets(
      '"Get New Topics Online" proceeds when online — no offline SnackBar, '
      'no network call is made',
      (tester) async {
        // No plan seeded → button is "Plan My Term".
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');

        await _pumpLessonsList(tester, db: db, fixture: fixture);

        await tester.tap(find.text('Plan My Term'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Get New Topics Online'));
        // The guard resolves via the wifi connectivity fake (no DNS), then
        // the forced-AI path constructs AiService — which throws in tests
        // (Supabase uninitialized) and is caught by _runAutoGenerate. Use
        // explicit pumps: the loading dialog animates, so pumpAndSettle
        // would time out.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));

        expect(
          find.text('This option needs an internet connection.'),
          findsNothing,
          reason: 'Online option must not show the offline SnackBar',
        );
        // The flow got past the online guard into the forced-AI path, where
        // the AI service construction throws before any HTTP request — so no
        // network call is made.
        expect(find.textContaining('Could not create plan'), findsOneWidget);
      },
    );
  });
}
