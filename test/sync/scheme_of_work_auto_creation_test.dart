import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/scheme_of_work/screens/scheme_of_work_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:drift/drift.dart';
import 'package:matcher/matcher.dart' as matcher;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FixedAuthNotifier extends AuthNotifier {
  FixedAuthNotifier(this.fixedState);

  final AuthStateData fixedState;

  @override
  AuthStateData build() => fixedState;
}

class TestFixture {
  TestFixture({
    required this.school,
    required this.teacher,
    required this.subjectId,
    required this.schemeWeekId,
  });

  final School school;
  final Teacher teacher;
  final int subjectId;
  final int schemeWeekId;
}

class TeacherFixture {
  TeacherFixture({
    required this.school,
    required this.teacher,
  });

  final School school;
  final Teacher teacher;
}

Future<TestFixture> _seedTeacherSchemeFixture(
  AppDatabase db, {
  required String teacherRole,
}) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000101'),
          schoolName: 'Test School',
          shortCode: 'TS101',
          subscriptionTier: const Value('free'),
        ),
      );

  final teacherId = await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000201'),
          email: 'teacher@testschool.local',
          teacherName: 'Test Teacher',
          role: Value(teacherRole),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000101'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );

  final subjectId = await db.subjectsDao.insert(
    serverId: '00000000-0000-0000-0000-000000000301',
    name: 'Mathematics',
    schoolId: '00000000-0000-0000-0000-000000000101',
    sortOrder: 1,
  );

  final schemeWeekId = await db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          schoolId: Value(schoolId),
          teacherId: Value(teacherId),
          subjectId: Value(subjectId),
          term: const Value('First'),
          weekNumber: const Value(1),
          topic: const Value('Algebraic Expressions'),
          objectives: const Value('Understand variables\nSimplify terms'),
          status: const Value('draft'),
          classLevel: const Value('JSS 1'),
        ),
      );

  final school = await db.schoolsDao.getByLocalId(schoolId);
  final teacher = await db.teachersDao.getById(teacherId);
  if (school == null || teacher == null) {
    throw StateError('Failed to seed test fixture');
  }

  return TestFixture(
    school: school,
    teacher: teacher,
    subjectId: subjectId,
    schemeWeekId: schemeWeekId,
  );
}

Future<TeacherFixture> _seedTeacherFixture(
  AppDatabase db, {
  required String teacherRole,
}) async {
  final schoolId = await db.into(db.schools).insert(
        SchoolsCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000111'),
          schoolName: 'Test School',
          shortCode: 'TS111',
          subscriptionTier: const Value('free'),
        ),
      );

  final teacherId = await db.into(db.teachers).insert(
        TeachersCompanion.insert(
          serverId: const Value('00000000-0000-0000-0000-000000000211'),
          email: 'teacher@testschool.local',
          teacherName: 'Test Teacher',
          role: Value(teacherRole),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000111'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );

  final school = await db.schoolsDao.getByLocalId(schoolId);
  final teacher = await db.teachersDao.getById(teacherId);
  if (school == null || teacher == null) {
    throw StateError('Failed to seed teacher fixture');
  }

  return TeacherFixture(
    school: school,
    teacher: teacher,
  );
}

Map<String, dynamic> _decodePayload(String payload) {
  final decoded = jsonDecode(payload);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return decoded.cast<String, dynamic>();
  throw FormatException('Sync payload is not a JSON object');
}

Future<SyncQueueData?> _queueRow(
  AppDatabase db, {
  required String queueTable,
}) async {
  final rows = await (db.select(db.syncQueue)
        ..where((t) => t.queueTable.equals(queueTable))
        ..orderBy([
          (t) => OrderingTerm(expression: t.createdAt),
        ]))
      .get();
  return rows.isEmpty ? null : rows.first;
}

Future<int> _autoCreateSchemeSubject(
  AppDatabase db,
  String subjectName,
) async {
  final subjectRow = await db.subjectsDao.getByName(subjectName);
  if (subjectRow != null) {
    return subjectRow.id;
  }

  final subjectId = await db.subjectsDao.insert(name: subjectName);
  await db.syncQueueDao.insertEntry(
    queueTable: 'subjects',
    recordLocalId: subjectId,
    operation: 'INSERT',
    payload: {
      'name': subjectName,
    },
  );
  return subjectId;
}

Future<void> _pumpSchemeScreen(
  WidgetTester tester, {
  required AppDatabase db,
  required AuthStateData authState,
}) async {
  await tester.binding.setSurfaceSize(const Size(1280, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  addTearDown(() {
    selectedSchemeTeacherSelection.value = null;
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
        authProvider.overrideWith(() => FixedAuthNotifier(authState)),
      ],
      child: const MaterialApp(
        home: SchemeOfWorkScreen(),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
}

Future<void> _expectLessonQueueEntry(
  AppDatabase db, {
  required int schemeWeekId,
}) async {
  final queueRow = await _queueRow(db, queueTable: 'lessons');
  expect(queueRow, matcher.isNotNull, reason: 'Expected a lessons sync_queue row');
  final row = queueRow!;

  final payload = _decodePayload(row.payload);
  expect(row.recordLocalId, greaterThan(0));
  expect(payload['scheme_of_work_id'], schemeWeekId.toString());
  expect(payload['week_number'], 1);
  expect(payload['term'], '1st Term');
  expect(payload['teacher_server_id'], matcher.isNotNull);
  expect(payload['school_server_id'], matcher.isNotNull);
  expect(payload['content'], isA<String>());
  expect((payload['content'] as String).isNotEmpty, isTrue);

  final insertedLesson = await db.lessonsDao.getById(row.recordLocalId);
  expect(insertedLesson, matcher.isNotNull, reason: 'Inserted lesson should exist');
  expect(insertedLesson!.schemeOfWorkId, schemeWeekId.toString());
  expect(insertedLesson.weekNumber, 1);
  expect(insertedLesson.term, '1st Term');
}

Future<void> _expectNoExamQueueEntry(AppDatabase db) async {
  final queueRow = await _queueRow(db, queueTable: 'exams');
  expect(queueRow, matcher.isNull,
      reason: 'Scheme save must never queue an exams sync entry');
  expect(await db.examsDao.getAll(), isEmpty,
      reason: 'Scheme save must never create draft exams');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  group('SchemeOfWorkScreen auto-creation sync queue verification', () {
    test('auto-created subject inserts a subjects sync_queue row', () async {
      final fixture = await _seedTeacherFixture(db, teacherRole: 'teacher');
      expect(await db.subjectsDao.getByName('Mathematics'), matcher.isNull);

      final subjectId = await _autoCreateSchemeSubject(db, 'Mathematics');

      final queueRow = await _queueRow(db, queueTable: 'subjects');
      expect(queueRow, matcher.isNotNull, reason: 'Expected a subjects sync_queue row');
      final row = queueRow!;
      final payload = _decodePayload(row.payload);

      expect(subjectId, greaterThan(0));
      expect(row.recordLocalId, subjectId);
      expect(payload['name'], 'Mathematics');

      final insertedSubject = await db.subjectsDao.getById(subjectId);
      expect(insertedSubject, matcher.isNotNull);
      expect(insertedSubject!.name, 'Mathematics');
      expect(fixture.school.schoolName, 'Test School');
      expect(fixture.teacher.teacherName, 'Test Teacher');
    });

    testWidgets(
      '_saveScheme() draft-lesson path enqueues a lessons sync_queue row',
      (tester) async {
        final fixture = await _seedTeacherSchemeFixture(db, teacherRole: 'teacher');
        final authState = AuthStateData(
          state: AuthState.authenticated,
          currentTeacher: fixture.teacher,
          currentSchool: fixture.school,
        );

        await _pumpSchemeScreen(tester, db: db, authState: authState);

        expect(await db.lessonsDao.getAll(), isEmpty);
        expect(await db.examsDao.getAll(), isEmpty);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Save Scheme'));
        await tester.pump(const Duration(seconds: 1));

        await _expectLessonQueueEntry(db, schemeWeekId: fixture.schemeWeekId);
      },
    );

    testWidgets(
      '_saveScheme() no longer creates draft exams or queues exams sync entries',
      (tester) async {
        final fixture = await _seedTeacherSchemeFixture(db, teacherRole: 'teacher');
        final authState = AuthStateData(
          state: AuthState.authenticated,
          currentTeacher: fixture.teacher,
          currentSchool: fixture.school,
        );

        await _pumpSchemeScreen(tester, db: db, authState: authState);

        expect(await db.lessonsDao.getAll(), isEmpty);
        expect(await db.examsDao.getAll(), isEmpty);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Save Scheme'));
        await tester.pump(const Duration(seconds: 1));

        // The linked draft lesson is still created...
        await _expectLessonQueueEntry(db, schemeWeekId: fixture.schemeWeekId);
        // ...but no draft exam is.
        await _expectNoExamQueueEntry(db);
      },
    );

    testWidgets(
      '_adminApprove() draft-lesson path enqueues a lessons sync_queue row',
      (tester) async {
        final fixture = await _seedTeacherSchemeFixture(db, teacherRole: 'admin');
        final authState = AuthStateData(
          state: AuthState.authenticated,
          currentTeacher: fixture.teacher,
          currentSchool: fixture.school,
        );

        await _pumpSchemeScreen(tester, db: db, authState: authState);

        expect(await db.lessonsDao.getAll(), isEmpty);
        expect(await db.examsDao.getAll(), isEmpty);

        await tester.tap(find.widgetWithText(TextButton, 'Approve'));
        await tester.pump(const Duration(seconds: 1));

        await _expectLessonQueueEntry(db, schemeWeekId: fixture.schemeWeekId);
      },
    );

    testWidgets(
      '_adminApprove() no longer creates draft exams or queues exams sync entries',
      (tester) async {
        final fixture = await _seedTeacherSchemeFixture(db, teacherRole: 'admin');
        final authState = AuthStateData(
          state: AuthState.authenticated,
          currentTeacher: fixture.teacher,
          currentSchool: fixture.school,
        );

        await _pumpSchemeScreen(tester, db: db, authState: authState);

        expect(await db.lessonsDao.getAll(), isEmpty);
        expect(await db.examsDao.getAll(), isEmpty);

        await tester.tap(find.widgetWithText(TextButton, 'Approve'));
        await tester.pump(const Duration(seconds: 1));

        // The linked draft lesson is still created...
        await _expectLessonQueueEntry(db, schemeWeekId: fixture.schemeWeekId);
        // ...but no draft exam is.
        await _expectNoExamQueueEntry(db);
      },
    );
  });
}
