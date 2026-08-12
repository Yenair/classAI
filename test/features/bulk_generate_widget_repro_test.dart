import 'package:classai/core/database/database.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/lesson/screens/lessons_list_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

Future<void> _seedConfig(AppDatabase db) async {
  await db.into(db.securityConfig).insert(
        SecurityConfigCompanion.insert(
          currentDeviceId: 'widget-test-device',
          lastRealtimeEventId: Value(0),
        ),
      );
}

Future<(int, int)> _seedAuth(AppDatabase db) async {
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
          role: Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000801'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );
  return (schoolId, teacherId);
}

/// Seeds one scheme row + linked draft lesson for a subject/class/term.
Future<void> _seedPlan(
  AppDatabase db, {
  required int schoolId,
  required int teacherId,
  required String subject,
  required String classLevel,
  required String termStorage,
}) async {
  final subjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-000000000a01',
    name: subject,
    schoolId: '00000000-0000-0000-0000-000000000801',
    sortOrder: 1,
  );
  final schemeId = await db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          schoolId: Value(schoolId),
          teacherId: Value(teacherId),
          subjectId: Value(subjectId),
          term: Value(termStorage),
          weekNumber: const Value(1),
          topic: const Value('Existing topic'),
          objectives: const Value('x'),
          status: const Value('draft'),
          classLevel: Value(classLevel),
        ),
      );
  await db.into(db.lessons).insert(
        LessonsCompanion.insert(
          subject: subject,
          classLevel: classLevel,
          week: 1,
          topic: 'Existing topic',
          difficulty: 'medium',
          bloomsVerbs: '',
          curriculum: 'NERDC',
          content: '{}',
          teacherServerId:
              const Value('00000000-0000-0000-0000-000000000901'),
          schoolServerId:
              const Value('00000000-0000-0000-0000-000000000801'),
          schemeOfWorkId: Value(schemeId.toString()),
          weekNumber: const Value(1),
          isUnlocked: const Value(false),
          status: const Value('draft'),
          term: const Value('1st Term'),
        ),
      );
}

Future<void> _pump(
  WidgetTester tester, {
  required AppDatabase db,
  required int schoolId,
  required int teacherId,
}) async {
  final school = await db.schoolsDao.getByLocalId(schoolId);
  final teacher = await db.teachersDao.getById(teacherId);
  final authState = AuthStateData(
    state: AuthState.authenticated,
    currentTeacher: teacher,
    currentSchool: school,
  );
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(
          () => FixedAuthNotifier(authState),
        ),
      ],
      child: const MaterialApp(home: LessonsListScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

/// Opens the plan dialog via Create → Bulk Generate.
Future<void> _openBulkGenerate(WidgetTester tester) async {
  await tester.tap(find.text('Create'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('📋  Bulk Generate'));
  await tester.pumpAndSettle();
}

/// Taps Bulk Offline Generate and pumps past generation + SnackBar.
Future<void> _tapOfflineGenerate(WidgetTester tester) async {
  await tester.tap(find.text('📋  Bulk Offline Generate'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late int schoolId;
  late int teacherId;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    await _seedConfig(db);
    ConnectivityPlatform.instance = _FakeConnectivityPlatform();
    SharedPreferences.setMockInitialValues({});
    (schoolId, teacherId) = await _seedAuth(db);
  });

  tearDown(() async {
    ConnectivityPlatform.instance = MethodChannelConnectivity();
    await db.close();
  });

  testWidgets('fresh Basic Science: no popup, 13 lessons', (tester) async {
    SharedPreferences.setMockInitialValues({
      'lessons_filter_subject': 'Basic Science',
      'lessons_filter_class': 'JSS 3',
      'lessons_filter_term': '1st Term',
    });
    await _pump(tester, db: db, schoolId: schoolId, teacherId: teacherId);

    await _openBulkGenerate(tester);
    // Not in refresh mode: dialog title is "Plan My Term".
    expect(find.text('Plan My Term'), findsOneWidget);
    expect(find.text('Refresh Plan'), findsNothing);

    await _tapOfflineGenerate(tester);

    expect(find.text('Refresh your plan?'), findsNothing,
        reason: 'No plan exists — the refresh confirmation must not appear');

    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    expect(schemeRows.length, 13);
    expect(lessons.length, 13);
  });

  testWidgets('fresh English Studies: no popup, 13 lessons', (tester) async {
    SharedPreferences.setMockInitialValues({
      'lessons_filter_subject': 'English Studies',
      'lessons_filter_class': 'JSS 1',
      'lessons_filter_term': '1st Term',
    });
    await _pump(tester, db: db, schoolId: schoolId, teacherId: teacherId);

    await _openBulkGenerate(tester);
    expect(find.text('Plan My Term'), findsOneWidget);

    await _tapOfflineGenerate(tester);

    expect(find.text('Refresh your plan?'), findsNothing);

    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    expect(schemeRows.length, 13);
    expect(lessons.length, 13);
  });

  testWidgets(
      'dialog switched to a fresh subject: no refresh popup, 13 lessons',
      (tester) async {
    // Seed a Mathematics plan so the PRE-FILL combo has a plan, then switch
    // the dialog to Basic Science — which has none.
    await _seedPlan(
      db,
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'Mathematics',
      classLevel: 'JSS 1',
      termStorage: 'First',
    );

    SharedPreferences.setMockInitialValues({
      'lessons_filter_subject': 'Mathematics',
      'lessons_filter_class': 'JSS 1',
      'lessons_filter_term': '1st Term',
    });
    await _pump(tester, db: db, schoolId: schoolId, teacherId: teacherId);

    await _openBulkGenerate(tester);
    // Pre-fill has a plan → dialog is in refresh mode.
    expect(find.text('Refresh Plan'), findsOneWidget);

    // Switch Subject → Basic Science and Class → JSS 3.
    final dialogDropdowns = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(DropdownButtonFormField<String>),
    );
    await tester.tap(dialogDropdowns.first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Basic Science').last);
    await tester.pumpAndSettle();
    await tester.tap(dialogDropdowns.at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('JSS 3').last);
    await tester.pumpAndSettle();

    await _tapOfflineGenerate(tester);

    // The final selection has no plan → no refresh confirmation.
    expect(find.text('Refresh your plan?'), findsNothing,
        reason: 'Selection changed to a subject with no plan; the refresh '
            'confirmation must not appear');

    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    // 13 new Basic Science rows + the untouched Mathematics plan row.
    expect(schemeRows.length, 14);
    expect(lessons.where((l) => l.subject == 'Basic Science'), hasLength(13));
    // The Mathematics plan (and its lesson) was not touched by the
    // Basic Science generation.
    expect(
      lessons.any((l) => l.subject == 'Mathematics' && !l.isDeleted),
      isTrue,
    );
  });

  testWidgets('class filter "JSS3" (no space) still generates for JSS 3',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'lessons_filter_subject': 'Basic Science',
      'lessons_filter_class': 'JSS3',
      'lessons_filter_term': '1st Term',
    });
    await _pump(tester, db: db, schoolId: schoolId, teacherId: teacherId);

    await _openBulkGenerate(tester);
    expect(find.text('Plan My Term'), findsOneWidget);

    await _tapOfflineGenerate(tester);

    expect(find.text('Refresh your plan?'), findsNothing);

    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    expect(schemeRows.length, 13);
    expect(lessons.length, 13);
    // Lessons must be stored under the canonical class the user picked.
    expect(
      lessons.every((l) => l.classLevel == 'JSS 3'),
      isTrue,
      reason: 'The no-space class value must not fall back to JSS 1',
    );
  });

  testWidgets('existing plan for the selection: popup appears, atomic replace',
      (tester) async {
    await _seedPlan(
      db,
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termStorage: 'First',
    );

    SharedPreferences.setMockInitialValues({
      'lessons_filter_subject': 'Basic Science',
      'lessons_filter_class': 'JSS 3',
      'lessons_filter_term': '1st Term',
    });
    await _pump(tester, db: db, schoolId: schoolId, teacherId: teacherId);

    await _openBulkGenerate(tester);
    expect(find.text('Refresh Plan'), findsOneWidget);

    await _tapOfflineGenerate(tester);

    // A plan exists for the selection → confirmation appears.
    expect(find.text('Refresh your plan?'), findsOneWidget);

    await tester.tap(find.text('Refresh Plan'));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // Old plan replaced: 13 fresh rows, old lesson soft-deleted, 13 live
    // lessons remain.
    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    expect(schemeRows.length, 13);
    final liveLessons = lessons.where((l) => !l.isDeleted).toList();
    expect(liveLessons.length, 13);
    // The old plan was atomically replaced: its lesson is soft-deleted.
    expect(lessons.where((l) => l.isDeleted), hasLength(1));
    expect(schemeRows.every((s) => s.topic != 'Existing topic'), isTrue);
    expect(liveLessons.every((l) => l.topic != 'Existing topic'), isTrue);
  });
}
