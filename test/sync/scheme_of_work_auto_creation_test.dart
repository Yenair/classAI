import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/features/scheme_of_work/screens/scheme_of_work_screen.dart';
import 'package:classai/main.dart' show databaseProvider;
import 'package:drift/drift.dart' hide isNotNull;
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
  expect(queueRow, isNotNull, reason: 'Expected a lessons sync_queue row');
  final row = queueRow!;

  final payload = _decodePayload(row.payload);
  expect(row.recordLocalId, greaterThan(0));
  expect(payload['scheme_of_work_id'], schemeWeekId.toString());
  expect(payload['week_number'], 1);
  expect(payload['term'], '1st Term');
  expect(payload['teacher_server_id'], isNotNull);
  expect(payload['school_server_id'], isNotNull);
  expect(payload['content'], isA<String>());
  expect((payload['content'] as String).isNotEmpty, isTrue);

  final insertedLesson = await db.lessonsDao.getById(row.recordLocalId);
  expect(insertedLesson, isNotNull, reason: 'Inserted lesson should exist');
  expect(insertedLesson!.schemeOfWorkId, schemeWeekId.toString());
  expect(insertedLesson.weekNumber, 1);
  expect(insertedLesson.term, '1st Term');
}

Future<void> _expectExamQueueEntry(
  AppDatabase db, {
  required int schemeWeekId,
}) async {
  final queueRow = await _queueRow(db, queueTable: 'exams');
  expect(queueRow, isNotNull, reason: 'Expected an exams sync_queue row');
  final row = queueRow!;

  final payload = _decodePayload(row.payload);
  expect(row.recordLocalId, greaterThan(0));
  expect(payload['scheme_of_work_id'], schemeWeekId.toString());
  expect(payload['week_number'], 1);
  expect(payload['term'], '1st Term');
  expect(payload['teacher_server_id'], isNotNull);
  expect(payload['school_server_id'], isNotNull);
  expect(payload['content'], isA<String>());
  expect((payload['content'] as String).isNotEmpty, isTrue);

  final insertedExam = await db.examsDao.getById(row.recordLocalId);
  expect(insertedExam, isNotNull, reason: 'Inserted exam should exist');
  expect(insertedExam!.schemeOfWorkId, schemeWeekId.toString());
  expect(insertedExam.weekNumber, 1);
  expect(insertedExam.term, '1st Term');
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
      '_saveScheme() draft-exam path enqueues an exams sync_queue row',
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

        await _expectExamQueueEntry(db, schemeWeekId: fixture.schemeWeekId);
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
      '_adminApprove() draft-exam path enqueues an exams sync_queue row',
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

        await _expectExamQueueEntry(db, schemeWeekId: fixture.schemeWeekId);
      },
    );
  });
}
