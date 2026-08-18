// Widget tests for the dashboard Recent Lessons cards' secondary status
// chips (Generated / Needs Sync), mirroring the lessons list chip logic.
//
// Pumped through the real DashboardScreen so the chips are verified in their
// actual production layout. The shared StatusChip widgets are the only
// StatusChips on the dashboard, so `find.byType(StatusChip)` is scoped to
// the lesson cards.

import 'package:classai/core/database/database.dart';
import 'package:classai/core/providers/config_provider.dart';
import 'package:classai/core/services/config_service.dart';
import 'package:classai/core/widgets/status_chip.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/dashboard/screens/dashboard_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    required this.school,
    required this.teacher,
  });

  final School school;
  final Teacher teacher;
}

Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
        SecurityConfigCompanion.insert(
          currentDeviceId: 'dashboard-chips-test-device',
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
  return _AuthFixture(school: school, teacher: teacher);
}

Future<void> _seedLesson(
  AppDatabase db,
  _AuthFixture fixture, {
  required String topic,
  String status = 'draft',
  bool unlocked = false,
  String? serverId,
}) {
  return db.lessonsDao.insertLesson(
    LessonsCompanion.insert(
      subject: 'Mathematics',
      classLevel: 'JSS 1',
      week: 1,
      topic: topic,
      difficulty: 'medium',
      bloomsVerbs: '',
      curriculum: 'NERDC',
      content: '{"objectives":[],"diagrams":[]}',
      teacherServerId: Value(fixture.teacher.serverId),
      schoolServerId: Value(fixture.school.serverId),
      term: const Value('1st Term'),
      status: Value(status),
      isUnlocked: Value(unlocked),
      serverId: Value(serverId),
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

/// Pumps the real DashboardScreen. On the test host (non-mobile) it renders
/// the editor layout; the Recent Lessons section loads lessons from the DB.
/// We pump repeatedly so the async provider work settles (pumpAndSettle
/// would time out because the dashboard's async providers never fully
/// settle in isolation).
Future<void> _pumpDashboard(
  WidgetTester tester, {
  required AppDatabase db,
  required FixedAuthNotifier notifier,
  Size surfaceSize = const Size(1400, 1200),
  double textScale = 1.0,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(() => notifier),
        configServiceProvider.overrideWithValue(
          ConfigService(client: buildMockSupabase()),
        ),
      ],
      child: MaterialApp(
        // The test font (Ahem) renders every glyph as a fontSize-wide
        // square, so narrow-width pumps scale text like the other layout
        // tests to avoid unrelated Ahem-only overflows outside the lesson
        // cards. linear(1.0) is a no-op for the default width pumps.
        builder: (context, widget) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: widget!,
        ),
        home: const DashboardScreen(),
      ),
    ),
  );

  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

/// Status chips inside the dashboard card whose title is [topic].
Finder _chipsInLessonCard(String topic) => find.descendant(
      of: find.ancestor(
        of: find.text(topic),
        matching: find.byType(InkWell),
      ),
      matching: find.byType(StatusChip),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late _AuthFixture fixture;
  late FixedAuthNotifier notifier;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    await _seedConfig(db);
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'editor',
    });
    fixture = await _seedAuth(db);
    notifier = FixedAuthNotifier(_authState(fixture));
  });

  tearDown(() async {
    ConnectivityPlatform.instance = MethodChannelConnectivity();
    await db.close();
  });

  testWidgets(
    'dashboard lesson cards show the Generated chip only while locked '
    'and the Needs Sync chip only without a serverId',
    (tester) async {
      await _seedLesson(
        db,
        fixture,
        topic: 'Locked Generated Unsynced',
        status: 'generated',
      );
      await _seedLesson(
        db,
        fixture,
        topic: 'Unlocked Generated Unsynced',
        status: 'generated',
        unlocked: true,
      );
      await _seedLesson(
        db,
        fixture,
        topic: 'Locked Generated Synced',
        status: 'generated',
        serverId: '00000000-0000-0000-0000-00000000ef01',
      );
      await _seedLesson(
        db,
        fixture,
        topic: 'Draft Synced',
        serverId: '00000000-0000-0000-0000-00000000ef02',
      );

      await _pumpDashboard(tester, db: db, notifier: notifier);

      // All four seeded lessons render on the Recent Lessons cards.
      expect(find.text('Locked Generated Unsynced'), findsOneWidget);
      expect(find.text('Unlocked Generated Unsynced'), findsOneWidget);
      expect(find.text('Locked Generated Synced'), findsOneWidget);
      expect(find.text('Draft Synced'), findsOneWidget);

      // Exactly two lessons carry each secondary chip: Generated on the two
      // locked generated lessons, Needs Sync on the two serverId-less ones.
      final chips = find.byType(StatusChip);
      expect(
        find.descendant(of: chips, matching: find.text('Generated')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: chips,
          matching: find.byIcon(Icons.lock_open_rounded),
        ),
        findsNWidgets(2),
      );
      expect(
        find.descendant(of: chips, matching: find.text('Needs Sync')),
        findsNWidgets(2),
      );
      expect(
        find.descendant(
          of: chips,
          matching: find.byIcon(Icons.sync_rounded),
        ),
        findsNWidgets(2),
      );

      // Scoped per card: locked generated + unsynced shows both chips.
      expect(
        find.descendant(
          of: _chipsInLessonCard('Locked Generated Unsynced'),
          matching: find.text('Generated'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _chipsInLessonCard('Locked Generated Unsynced'),
          matching: find.text('Needs Sync'),
        ),
        findsOneWidget,
      );

      // Unlocked: the secondary Generated chip must NOT appear (the primary
      // badge already conveys generated), but Needs Sync remains.
      expect(
        find.descendant(
          of: _chipsInLessonCard('Unlocked Generated Unsynced'),
          matching: find.text('Generated'),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _chipsInLessonCard('Unlocked Generated Unsynced'),
          matching: find.byIcon(Icons.lock_open_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: _chipsInLessonCard('Unlocked Generated Unsynced'),
          matching: find.text('Needs Sync'),
        ),
        findsOneWidget,
      );

      // Synced: Generated stays for locked lessons, Needs Sync disappears.
      expect(
        find.descendant(
          of: _chipsInLessonCard('Locked Generated Synced'),
          matching: find.text('Generated'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: _chipsInLessonCard('Locked Generated Synced'),
          matching: find.text('Needs Sync'),
        ),
        findsNothing,
      );

      // A plain synced draft shows no secondary chips at all.
      expect(_chipsInLessonCard('Draft Synced'), findsNothing);
    },
  );

  testWidgets('dashboard lesson cards do not overflow at 320dp width',
      (tester) async {
    await _seedLesson(db, fixture, topic: 'Narrow Dashboard Lesson');
    // 320dp is below the 600dp editor/reader breakpoint, so force the phone
    // (reader) layout and scale text like the other layout tests so only the
    // lesson card chip row is under test.
    SharedPreferences.setMockInitialValues({
      'platform_mode_override': 'reader',
    });

    await _pumpDashboard(
      tester,
      db: db,
      notifier: notifier,
      surfaceSize: const Size(320, 1200),
      textScale: 0.55,
    );

    // The primary Draft badge and the secondary Needs Sync chip render on
    // the narrow card.
    expect(find.text('DRAFT'), findsOneWidget);
    final chips = find.byType(StatusChip);
    expect(
      find.descendant(of: chips, matching: find.text('Needs Sync')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: chips,
        matching: find.byIcon(Icons.sync_rounded),
      ),
      findsOneWidget,
    );
    // A RenderFlex overflow during layout would be reported here and
    // fail the test.
    expect(tester.takeException(), isNull);
  });
}
