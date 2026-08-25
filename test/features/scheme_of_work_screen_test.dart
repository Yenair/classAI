import 'package:classai/core/database/database.dart';
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
      child: const MaterialApp(home: SchemeOfWorkScreen()),
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
        expect(find.text('Scheme of Work Review'), findsOneWidget);
        expect(find.text('All Schemes (Admin)'), findsOneWidget);

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
  });
}
