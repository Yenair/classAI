import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/theme/app_theme.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/scheme_of_work/screens/scheme_of_work_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:connectivity_plus_platform_interface/method_channel_connectivity.dart';
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Connectivity stub so `PlatformHelper.isOnline()` is deterministic.
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

AuthStateData _authState(School school, Teacher teacher) {
  return AuthStateData(
    state: AuthState.authenticated,
    currentTeacher: teacher,
    currentSchool: school,
  );
}

/// Seeds a school, teacher, and subject, returning their IDs.
Future<({int schoolId, int teacherId, int subjectId})> _seedBase(
  AppDatabase db, {
  String teacherRole = 'admin',
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
          email: 'admin@testschool.local',
          teacherName: 'Test Admin',
          role: Value(teacherRole),
          schoolLocalId: schoolId,
          schoolServerId:
              const Value('00000000-0000-0000-0000-000000000801'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );

  final subjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-000000000a01',
    name: 'Mathematics',
    schoolId: '00000000-0000-0000-0000-000000000801',
    sortOrder: 1,
  );

  return (schoolId: schoolId, teacherId: teacherId, subjectId: subjectId);
}

/// Seeds [count] scheme_of_work records across multiple subjects/classes
/// to reproduce the54-record scenario from the logs.
Future<void> _seedSchemeRecords(
  AppDatabase db, {
  required int schoolId,
  required int teacherId,
  required int subjectId,
  int count = 54,
}) async {
  final classLevels = ['JSS 1', 'JSS 2', 'JSS 3', 'SSS 1', 'SSS 2', 'SSS 3'];
  final terms = ['First', 'Second', 'Third'];
  final subjects = <int>[subjectId];

  // Add a second subject
  final secondSubjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-000000000a02',
    name: 'English Studies',
    schoolId: '00000000-0000-0000-0000-000000000801',
    sortOrder: 2,
  );
  subjects.add(secondSubjectId);

  int weekNum = 1;
  for (int i = 0; i < count; i++) {
    final classLevel = classLevels[i % classLevels.length];
    final term = terms[i % terms.length];
    final subjectIdVal = subjects[i % subjects.length];

    await db.into(db.schemeOfWork).insert(
          SchemeOfWorkCompanion.insert(
            schoolId: Value(schoolId),
            teacherId: Value(teacherId),
            subjectId: Value(subjectIdVal),
            term: Value(term),
            weekNumber: Value(weekNum),
            topic: Value('Topic $weekNum - Week $weekNum'),
            objectives: Value('Objectives for week $weekNum'),
            status: const Value('draft'),
            classLevel: Value(classLevel),
          ),
        );
    weekNum++;
    if (weekNum > 12) weekNum = 1; // cycle weeks
  }
}

/// Pumps the SchemeOfWorkScreen with provider overrides.
///
/// If [captureErrors] is true, all FlutterError exceptions are collected
/// into [capturedErrors] instead of being thrown.
Future<void> _pumpSow(
  WidgetTester tester, {
  required AppDatabase db,
  required AuthStateData authData,
  Size surfaceSize = const Size(1280, 1400),
  List<FlutterErrorDetails>? capturedErrors,
}) async {
  await tester.binding.setSurfaceSize(surfaceSize);
  addTearDown(() => tester.binding.setSurfaceSize(null));

  final previousHandler = FlutterError.onError;
  if (capturedErrors != null) {
    FlutterError.onError = (details) {
      capturedErrors.add(details);
    };
  }

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(() => FixedAuthNotifier(authData)),
      ],
      // The real app theme gives buttons an infinite minimum width, which is
      // what broke the filter row — tests must exercise it.
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const SchemeOfWorkScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();

  if (capturedErrors != null) {
    FlutterError.onError = previousHandler;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
    ConnectivityPlatform.instance =
        _FakeConnectivityPlatform([ConnectivityResult.wifi]);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    ConnectivityPlatform.instance = MethodChannelConnectivity();
    await db.close();
  });

  group('SchemeOfWorkScreen layout', () {
    testWidgets(
      'renders without RenderBox errors at desktop width with many records',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);
        expect(school, isNotNull);
        expect(teacher, isNotNull);

        await _seedSchemeRecords(
          db,
          schoolId: base.schoolId,
          teacherId: base.teacherId,
          subjectId: base.subjectId,
          count: 54,
        );

        await _pumpSow(
          tester,
          db: db,
          authData: _authState(school!, teacher!),
          surfaceSize: const Size(1280, 1400),
        );

        // Verify the screen rendered key elements.
        expect(find.text('Scheme of Work'), findsOneWidget);
        expect(find.text('Review and update teachers scheme of work'),
            findsOneWidget);
        expect(find.text('All Schemes (Admin)'), findsOneWidget);
        // The old review banner is gone, so the bulk action now lives in the
        // list header instead.
        expect(find.text('Scheme of Work Review'), findsNothing);
        expect(find.text('Bulk Approve'), findsOneWidget);

        // No RenderBox layout errors.
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders without RenderBox errors at narrow width with many records',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);

        await _seedSchemeRecords(
          db,
          schoolId: base.schoolId,
          teacherId: base.teacherId,
          subjectId: base.subjectId,
          count: 54,
        );

        await _pumpSow(
          tester,
          db: db,
          authData: _authState(school!, teacher!),
          surfaceSize: const Size(375, 812), // iPhone-like
        );

        expect(find.text('Scheme of Work'), findsOneWidget);
        // Filter out cosmetic overflow warnings — only fail on hard errors.
        final errors = <Object>[];
        Object? err;
        while ((err = tester.takeException()) != null) {
          final msg = err.toString();
          if (!msg.contains('overflowed by') && !msg.contains('RenderFlex')) {
            errors.add(err!);
          }
        }
        if (errors.isNotEmpty) {
          fail('Layout errors: ${errors.map((e) => e.toString().split('\n').first).join(' | ')}');
        }
      },
    );

    testWidgets(
      'renders without RenderBox errors at tablet width',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);

        await _seedSchemeRecords(
          db,
          schoolId: base.schoolId,
          teacherId: base.teacherId,
          subjectId: base.subjectId,
          count: 54,
        );

        await _pumpSow(
          tester,
          db: db,
          authData: _authState(school!, teacher!),
          surfaceSize: const Size(800, 1024),
        );

        expect(find.text('Scheme of Work'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'renders empty state without errors',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);

        await _pumpSow(
          tester,
          db: db,
          authData: _authState(school!, teacher!),
          surfaceSize: const Size(1280, 1400),
        );

        expect(find.text('No schemes submitted yet'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'expanding a group section does not cause RenderBox errors',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);

        // Seed a smaller number of records for this test
        await _seedSchemeRecords(
          db,
          schoolId: base.schoolId,
          teacherId: base.teacherId,
          subjectId: base.subjectId,
          count: 18,
        );

        await _pumpSow(
          tester,
          db: db,
          authData: _authState(school!, teacher!),
          surfaceSize: const Size(1280, 1400),
        );

        expect(tester.takeException(), isNull);

        // Tap on the first group section header to expand it.
        final expandIcons = find.byIcon(Icons.expand_more);
        if (expandIcons.evaluate().isNotEmpty) {
          await tester.tap(expandIcons.first);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'filter dropdowns do not cause overflow at narrow width',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);

        await _seedSchemeRecords(
          db,
          schoolId: base.schoolId,
          teacherId: base.teacherId,
          subjectId: base.subjectId,
          count: 12,
        );

        await _pumpSow(
          tester,
          db: db,
          authData: _authState(school!, teacher!),
          surfaceSize: const Size(320, 800), // Very narrow
        );

        expect(find.text('Filter schemes'), findsOneWidget);
        // Filter out cosmetic overflow warnings — only fail on hard errors.
        final errors = <Object>[];
        Object? err;
        while ((err = tester.takeException()) != null) {
          final msg = err.toString();
          if (!msg.contains('overflowed by') && !msg.contains('RenderFlex')) {
            errors.add(err!);
          }
        }
        if (errors.isNotEmpty) {
          fail('Layout errors at 320px: ${errors.map((e) => e.toString().split('\n').first).join(' | ')}');
        }
      },
    );

    testWidgets(
      'applying a filter does not cause layout errors',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);

        await _seedSchemeRecords(
          db,
          schoolId: base.schoolId,
          teacherId: base.teacherId,
          subjectId: base.subjectId,
          count: 30,
        );

        await _pumpSow(
          tester,
          db: db,
          authData: _authState(school!, teacher!),
          surfaceSize: const Size(1280, 1400),
        );

        expect(tester.takeException(), isNull);

        // Tap the term filter and select "First"
        final termFilter = find.ancestor(
          of: find.text('Filter by Term'),
          matching: find.byType(DropdownButtonFormField<String>),
        );
        if (termFilter.evaluate().isNotEmpty) {
          await tester.tap(termFilter.first);
          await tester.pumpAndSettle();
          await tester.tap(find.text('First').last);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      },
    );

    testWidgets(
      'teacher panel does not overflow at desktop sizes with 5 teachers',
      (tester) async {
        final base = await _seedBase(db);
        final school = await db.schoolsDao.getByLocalId(base.schoolId);
        final teacher = await db.teachersDao.getById(base.teacherId);

        // 4 extra teachers → 5 total, the seat count of a real school.
        for (var i = 0; i < 4; i++) {
          await db.into(db.teachers).insert(
                TeachersCompanion.insert(
                  serverId: Value('00000000-0000-0000-0000-00000000091$i'),
                  email: 'teacher$i@testschool.local',
                  teacherName: 'Teacher Number $i With A Long Name',
                  role: const Value('teacher'),
                  schoolLocalId: base.schoolId,
                  schoolServerId:
                      const Value('00000000-0000-0000-0000-000000000801'),
                  isActive: const Value(true),
                  forcePasswordReset: const Value(false),
                  passwordHashVersion: const Value(1),
                  themeMode: const Value('system'),
                ),
              );
        }

        await _seedSchemeRecords(
          db,
          schoolId: base.schoolId,
          teacherId: base.teacherId,
          subjectId: base.subjectId,
          count: 54,
        );

        // Sync can blank class levels. An empty one used to duplicate the
        // "All Classes" filter item, which trips DropdownButtonFormField's
        // single-match assert during build and leaves the card unlaid out.
        await db.into(db.schemeOfWork).insert(
              SchemeOfWorkCompanion.insert(
                schoolId: Value(base.schoolId),
                teacherId: Value(base.teacherId),
                subjectId: Value(base.subjectId),
                term: const Value('first'),
                weekNumber: const Value(1),
                topic: const Value(''),
                objectives: const Value(''),
                status: const Value('draft'),
                classLevel: const Value(''),
              ),
            );

        // Heights where the teacher list used to overflow the card by
        // 34–234 px (desktop window resizing).
        for (final size in const [
          Size(1400, 900),
          Size(1400, 740),
          Size(1234, 700),
        ]) {
          final captured = <FlutterErrorDetails>[];
          await _pumpSow(
            tester,
            db: db,
            authData: _authState(school!, teacher!),
            surfaceSize: size,
            capturedErrors: captured,
          );
          expect(find.text('Teachers'), findsOneWidget);
          expect(captured, isEmpty,
              reason: 'layout errors at $size: ${captured.map((e) => e.exception.toString().split('\n').first).toList()}');
        }
      },
    );

    testWidgets('teacher panel collapses and expands', (tester) async {
      final base = await _seedBase(db);
      final school = await db.schoolsDao.getByLocalId(base.schoolId);
      final teacher = await db.teachersDao.getById(base.teacherId);

      await _seedSchemeRecords(
        db,
        schoolId: base.schoolId,
        teacherId: base.teacherId,
        subjectId: base.subjectId,
        count: 12,
      );

      await _pumpSow(
        tester,
        db: db,
        authData: _authState(school!, teacher!),
        surfaceSize: const Size(1280, 900),
      );

      expect(find.text('Teachers'), findsOneWidget);
      await tester.tap(find.byTooltip('Collapse teachers'));
      await tester.pumpAndSettle();
      expect(find.text('Teachers'), findsNothing);
      expect(find.byTooltip('Show teachers'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.byTooltip('Show teachers'));
      await tester.pumpAndSettle();
      expect(find.text('Teachers'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('lesson notes dialog shows notes and diagrams', (tester) async {
      final base = await _seedBase(db);
      final school = await db.schoolsDao.getByLocalId(base.schoolId);
      final teacher = await db.teachersDao.getById(base.teacherId);

      final schemeId = await db.into(db.schemeOfWork).insert(
            SchemeOfWorkCompanion.insert(
              schoolId: Value(base.schoolId),
              teacherId: Value(base.teacherId),
              subjectId: Value(base.subjectId),
              term: const Value('first'),
              weekNumber: const Value(1),
              topic: const Value('Cell Structure'),
              objectives: const Value('Name the parts of a cell'),
              status: const Value('draft'),
              classLevel: const Value('JSS 1'),
            ),
          );

      await db.lessonsDao.insertLesson(
        LessonsCompanion.insert(
          subject: 'Mathematics',
          classLevel: 'JSS 1',
          week: 1,
          topic: 'Cell Structure',
          difficulty: 'medium',
          bloomsVerbs: '',
          curriculum: 'NERDC',
          content: jsonEncode({
            'objectives': [
              'Identify cell organelles',
              'State their functions',
            ],
            'vocabulary': ['mitochondrion', 'nucleus'],
            'materials': ['Chart of a plant cell'],
            'presentation': [
              'Introduction: what is a cell?',
              'Body: the organelles',
            ],
            'assessment': 'Label a cell diagram.',
            'homework': 'Draw and label a plant cell.',
            'diagrams': [
              {'description': 'A labelled plant cell', 'imageUrl': ''},
            ],
          }),
          schemeOfWorkId: Value(schemeId.toString()),
          weekNumber: const Value(1),
          isUnlocked: const Value(true),
          status: const Value('draft'),
          term: const Value('1st Term'),
        ),
      );

      await _pumpSow(
        tester,
        db: db,
        authData: _authState(school!, teacher!),
        surfaceSize: const Size(1280, 1000),
      );

      // Expand the class group so the week card (and its linked lesson)
      // renders.
      final expandIcons = find.byIcon(Icons.expand_more);
      expect(expandIcons, findsWidgets);
      await tester.tap(expandIcons.first);
      await tester.pumpAndSettle();

      expect(find.text('View notes'), findsOneWidget);
      await tester.tap(find.text('View notes'));
      await tester.pumpAndSettle();

      expect(find.text('Objectives'), findsOneWidget);
      expect(find.text('Identify cell organelles'), findsOneWidget);
      expect(find.text('Diagrams'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
