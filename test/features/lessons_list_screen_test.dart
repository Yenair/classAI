import 'package:classai/core/database/database.dart';
import 'package:classai/core/widgets/status_chip.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/lesson/screens/lessons_list_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart';
import 'package:drift/drift.dart' hide isNotNull;
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
/// / 1st Term so the Create flyout offers "Refresh Plan".
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

/// Opens the "Create" flyout menu and waits for it to settle.
Future<void> _openCreateMenu(WidgetTester tester) async {
  await tester.tap(find.text('Create'));
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

  group('LessonsListScreen Create flyout', () {
    testWidgets(
      'offers "Refresh Plan" in the Create menu when a plan exists '
      'for the selected filters',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await _seedPlanFixture(db, fixture);

        await _pumpLessonsList(tester, db: db, fixture: fixture);

        // The compact "Create" flyout is the single AppBar action; menu
        // items are only visible once the menu is open.
        expect(find.text('Create'), findsOneWidget);
        expect(find.text('✏️  Add Single Lesson'), findsNothing);
        expect(find.text('📋  Bulk Generate'), findsNothing);
        expect(find.text('🔄  Refresh Plan'), findsNothing);

        await _openCreateMenu(tester);

        expect(find.text('✏️  Add Single Lesson'), findsOneWidget);
        expect(find.text('📋  Bulk Generate'), findsOneWidget);
        expect(find.text('🔄  Refresh Plan'), findsOneWidget);
        expect(find.byIcon(Icons.refresh_rounded), findsWidgets);
      },
    );

    testWidgets(
      'hides "Refresh Plan" from the Create menu when the filter combo '
      'has no plan',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await _seedPlanFixture(db, fixture);

        await _pumpLessonsList(tester, db: db, fixture: fixture);

        // Change the term filter to one with no plan (2nd Term).
        await tester.tap(_termFilterDropdown());
        await tester.pumpAndSettle();
        await tester.tap(find.text('2nd Term').last);
        await tester.pumpAndSettle();

        await _openCreateMenu(tester);

        expect(find.text('✏️  Add Single Lesson'), findsOneWidget);
        expect(find.text('📋  Bulk Generate'), findsOneWidget);
        expect(find.text('🔄  Refresh Plan'), findsNothing);
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

        // Open the Create menu and choose Refresh Plan.
        await _openCreateMenu(tester);
        await tester.tap(find.text('🔄  Refresh Plan'));
        await tester.pumpAndSettle();

        // The plan dialog opens in refresh mode with both generation options.
        expect(find.text('Refresh Plan'), findsOneWidget);
        expect(find.text('📋  Bulk Offline Generate'), findsOneWidget);
        expect(find.text('🌐  Bulk Online Generate'), findsOneWidget);
        expect(find.text('Refresh your plan?'), findsNothing);

        // Pick offline → confirmation dialog with warning copy.
        await tester.tap(find.text('📋  Bulk Offline Generate'));
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
      '"Bulk Online Generate" proceeds when online — no offline SnackBar, '
      'no network call is made',
      (tester) async {
        // No plan seeded → dialog is in create mode.
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');

        await _pumpLessonsList(tester, db: db, fixture: fixture);

        await _openCreateMenu(tester);
        await tester.tap(find.text('📋  Bulk Generate'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('🌐  Bulk Online Generate'));
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

  group('LessonsListScreen delete / Undo', () {
    testWidgets(
      'deleting a lesson offers Undo, restores the row and drops the held '
      'DELETE entry',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        final lessonId = await db.lessonsDao.insertLesson(
          LessonsCompanion.insert(
            subject: 'Mathematics',
            classLevel: 'JSS 1',
            week: 1,
            topic: 'Algebraic Expressions',
            difficulty: 'medium',
            bloomsVerbs: '',
            curriculum: 'NERDC',
            content: '{"objectives":[],"diagrams":[]}',
            teacherServerId: Value(fixture.teacher.serverId),
            schoolServerId: Value(fixture.school.serverId),
            serverId: const Value('00000000-0000-0000-0000-00000000ee01'),
            // The test harness pre-filters by subject/class/term, so the
            // seeded lesson must match those filters to stay visible.
            term: const Value('1st Term'),
          ),
        );
        await _pumpLessonsList(tester, db: db, fixture: fixture);

        await tester.tap(find.byTooltip('Delete'));
        await tester.pumpAndSettle();
        expect(find.text('Delete Lesson'), findsOneWidget);
        await tester.tap(find.text('Delete'));
        await tester.pumpAndSettle();

        expect(find.text('Lesson deleted'), findsOneWidget);
        expect(await db.lessonsDao.getAll(), isEmpty,
            reason: 'the lesson is soft-deleted immediately');
        final deletes = (await db.syncQueueDao.pendingEntries())
            .where((e) =>
                e.queueTable == 'lessons' && e.operation == 'DELETE')
            .toList();
        expect(deletes, hasLength(1));
        expect(deletes.single.recordLocalId, lessonId);
        expect(deletes.single.nextRetryAt, isNotNull,
            reason: 'the DELETE entry is held until the Undo window elapses');

        await tester.tap(find.text('Undo'));
        await tester.pumpAndSettle();
        expect((await db.lessonsDao.getAll()).length, 1,
            reason: 'Undo restores the lesson locally');
        expect(
          (await db.syncQueueDao.pendingEntries())
              .where((e) =>
                  e.queueTable == 'lessons' && e.operation == 'DELETE'),
          isEmpty,
          reason: 'Undo drops the new DELETE entry so the server row is kept',
        );
      },
    );
  });

  testWidgets(
    'lesson cards show icon+text status chips (Draft / Completed)',
    (tester) async {
      fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
      await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: 'Mathematics',
          classLevel: 'JSS 1',
          week: 1,
          topic: 'Draft Lesson',
          difficulty: 'medium',
          bloomsVerbs: '',
          curriculum: 'NERDC',
          content: '{"objectives":[],"diagrams":[]}',
          teacherServerId: Value(fixture.teacher.serverId),
          schoolServerId: Value(fixture.school.serverId),
          term: const Value('1st Term'),
        ),
      );
      await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: 'Mathematics',
          classLevel: 'JSS 1',
          week: 2,
          topic: 'Completed Lesson',
          difficulty: 'medium',
          bloomsVerbs: '',
          curriculum: 'NERDC',
          content: '{"objectives":[{"text":"done"}],"diagrams":[]}',
          teacherServerId: Value(fixture.teacher.serverId),
          schoolServerId: Value(fixture.school.serverId),
          term: const Value('1st Term'),
          status: const Value('completed'),
          isUnlocked: const Value(true),
        ),
      );
      await _pumpLessonsList(tester, db: db, fixture: fixture);

      final chips = find.byType(StatusChip);
      expect(
        find.descendant(of: chips, matching: find.text('Draft')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: chips,
          matching: find.byIcon(Icons.edit_note_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.text('Completed')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: chips,
          matching: find.byIcon(Icons.check_circle_rounded),
        ),
        findsOneWidget,
      );
    },
  );

  group('LessonsListScreen secondary status chips', () {
    testWidgets(
      'a generated but locked lesson shows Draft + Generated + Needs Sync',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await db.lessonsDao.insertLesson(
          LessonsCompanion.insert(
            subject: 'Mathematics',
            classLevel: 'JSS 1',
            week: 1,
            topic: 'Generated Locked Lesson',
            difficulty: 'medium',
            bloomsVerbs: '',
            curriculum: 'NERDC',
            content: '{"objectives":[],"diagrams":[]}',
            teacherServerId: Value(fixture.teacher.serverId),
            schoolServerId: Value(fixture.school.serverId),
            term: const Value('1st Term'),
            status: const Value('generated'),
            // No serverId -> Needs Sync applies.
          ),
        );
        await _pumpLessonsList(tester, db: db, fixture: fixture);

        final chips = find.byType(StatusChip);
        expect(
          find.descendant(of: chips, matching: find.text('Draft')),
          findsOneWidget,
          reason: 'the locked generated lesson keeps its primary Draft chip',
        );
        expect(
          find.descendant(of: chips, matching: find.text('Generated')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: chips,
            matching: find.byIcon(Icons.lock_open_rounded),
          ),
          findsOneWidget,
        );
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
      },
    );

    testWidgets(
      'a generated but unlocked lesson hides the secondary Generated chip',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await db.lessonsDao.insertLesson(
          LessonsCompanion.insert(
            subject: 'Mathematics',
            classLevel: 'JSS 1',
            week: 1,
            topic: 'Generated Unlocked Lesson',
            difficulty: 'medium',
            bloomsVerbs: '',
            curriculum: 'NERDC',
            content: '{"objectives":[],"diagrams":[]}',
            teacherServerId: Value(fixture.teacher.serverId),
            schoolServerId: Value(fixture.school.serverId),
            term: const Value('1st Term'),
            status: const Value('generated'),
            isUnlocked: const Value(true),
          ),
        );
        await _pumpLessonsList(tester, db: db, fixture: fixture);

        final chips = find.byType(StatusChip);
        expect(
          find.descendant(of: chips, matching: find.text('Unlocked')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: chips,
            matching: find.byIcon(Icons.auto_awesome_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: chips, matching: find.text('Generated')),
          findsNothing,
          reason: 'Unlocked already conveys generated, so no secondary chip',
        );
        expect(
          find.descendant(
            of: chips,
            matching: find.byIcon(Icons.lock_open_rounded),
          ),
          findsNothing,
        );
        // Still no serverId, so Needs Sync remains.
        expect(
          find.descendant(of: chips, matching: find.text('Needs Sync')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'a generated lesson with a serverId hides Needs Sync',
      (tester) async {
        fixture = await _seedAuthFixture(db, teacherRole: 'teacher');
        await db.lessonsDao.insertLesson(
          LessonsCompanion.insert(
            subject: 'Mathematics',
            classLevel: 'JSS 1',
            week: 1,
            topic: 'Synced Generated Lesson',
            difficulty: 'medium',
            bloomsVerbs: '',
            curriculum: 'NERDC',
            content: '{"objectives":[],"diagrams":[]}',
            teacherServerId: Value(fixture.teacher.serverId),
            schoolServerId: Value(fixture.school.serverId),
            term: const Value('1st Term'),
            status: const Value('generated'),
            serverId: const Value('00000000-0000-0000-0000-00000000ef01'),
          ),
        );
        await _pumpLessonsList(tester, db: db, fixture: fixture);

        final chips = find.byType(StatusChip);
        expect(
          find.descendant(of: chips, matching: find.text('Generated')),
          findsOneWidget,
        );
        expect(
          find.descendant(of: chips, matching: find.text('Needs Sync')),
          findsNothing,
        );
        expect(
          find.descendant(
            of: chips,
            matching: find.byIcon(Icons.sync_rounded),
          ),
          findsNothing,
        );
      },
    );
  });
}
