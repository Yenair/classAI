import 'package:classai/core/data/nerdc_curriculum.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

/// Temporary reproduction: does saveScheme write all 13 weeks for
/// Basic Science JSS 3 1st Term, with and without deleteExistingFirst?
Future<(int, int)> _seedAuth(AppDatabase db) async {
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
          role: Value('teacher'),
          schoolLocalId: schoolId,
          schoolServerId: const Value('00000000-0000-0000-0000-000000000101'),
          isActive: const Value(true),
          forcePasswordReset: const Value(false),
          passwordHashVersion: const Value(1),
          themeMode: const Value('system'),
        ),
      );
  return (schoolId, teacherId);
}

void main() {
  test('curated Basic Science JSS3 1st has 13 weeks', () {
    final topics = getNerdcTopics('Basic Science', 'JSS 3', '1st Term');
    expect(topics, isNotNull);
    expect(topics!.length, 13);
  });

  test('saveScheme writes all 13 weeks + 13 lessons (fresh, no delete)',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final (schoolId, teacherId) = await _seedAuth(db);

    final topics = getNerdcTopics('Basic Science', 'JSS 3', '1st Term')!;
    final weeks = [
      for (var i = 0; i < topics.length; i++)
        {
          'week': i + 1,
          'topic': topics[i].topic,
          'objectives': topics[i].objectives.join('\n'),
        },
    ];
    expect(weeks.length, 13);

    final service = SchemeOfWorkService(db);
    await service.saveScheme(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      term: 'First',
      weeks: weeks,
      deleteExistingFirst: false,
    );

    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    // ignore: avoid_print
    print('saveScheme(fresh): schemeRows=${schemeRows.length} '
        'lessons=${lessons.length}');
    expect(schemeRows.length, 13);
    expect(lessons.length, 13);
  });

  test('saveScheme refresh over an existing 1-week plan yields 13', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final (schoolId, teacherId) = await _seedAuth(db);

    // Seed a 1-week Basic Science plan (leftover from a broken first run).
    final subjectId = await db.subjectsDao.insert(
      serverId: '00000000-0000-0000-0000-000000000301',
      name: 'Basic Science',
      schoolId: '00000000-0000-0000-0000-000000000101',
      sortOrder: 1,
    );
    await db.into(db.schemeOfWork).insert(
          SchemeOfWorkCompanion.insert(
            schoolId: Value(schoolId),
            teacherId: Value(teacherId),
            subjectId: Value(subjectId),
            term: const Value('First'),
            weekNumber: const Value(1),
            topic: const Value('Nervous System'),
            objectives: const Value('x'),
            status: const Value('draft'),
            classLevel: const Value('JSS 3'),
          ),
        );

    final topics = getNerdcTopics('Basic Science', 'JSS 3', '1st Term')!;
    final weeks = [
      for (var i = 0; i < topics.length; i++)
        {
          'week': i + 1,
          'topic': topics[i].topic,
          'objectives': topics[i].objectives.join('\n'),
        },
    ];

    final service = SchemeOfWorkService(db);
    await service.saveScheme(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      term: 'First',
      weeks: weeks,
      deleteExistingFirst: true,
    );

    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    // ignore: avoid_print
    print('saveScheme(refresh over existing): schemeRows=${schemeRows.length} '
        'lessons=${lessons.length}');
    expect(schemeRows.length, 13);
    expect(lessons.length, 13);
  });

  test('findSchemes does not match a different subject/class/term', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final (schoolId, teacherId) = await _seedAuth(db);

    // Only a Mathematics / JSS 1 / 1st Term plan exists.
    final subjectId = await db.subjectsDao.insert(
      serverId: '00000000-0000-0000-0000-000000000301',
      name: 'Mathematics',
      schoolId: '00000000-0000-0000-0000-000000000101',
      sortOrder: 1,
    );
    await db.into(db.schemeOfWork).insert(
          SchemeOfWorkCompanion.insert(
            schoolId: Value(schoolId),
            teacherId: Value(teacherId),
            subjectId: Value(subjectId),
            term: const Value('First'),
            weekNumber: const Value(1),
            topic: const Value('Algebraic Expressions'),
            objectives: const Value('x'),
            status: const Value('draft'),
            classLevel: const Value('JSS 1'),
          ),
        );

    final service = SchemeOfWorkService(db);
    final forMaths = await service.findSchemes(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'Mathematics',
      classLevel: 'JSS 1',
      term: '1st Term',
    );
    final forBasicScience = await service.findSchemes(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      term: '1st Term',
    );
    // ignore: avoid_print
    print('findSchemes: maths=${forMaths.length} '
        'basicScience=${forBasicScience.length}');
    expect(forMaths.length, 1);
    expect(forBasicScience, isEmpty,
        reason: 'A different subject/class/term must not match');
  });

  test('saveScheme writes all 13 weeks + 13 lessons (deleteExistingFirst)',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final (schoolId, teacherId) = await _seedAuth(db);

    final topics = getNerdcTopics('Basic Science', 'JSS 3', '1st Term')!;
    final weeks = [
      for (var i = 0; i < topics.length; i++)
        {
          'week': i + 1,
          'topic': topics[i].topic,
          'objectives': topics[i].objectives.join('\n'),
        },
    ];

    final service = SchemeOfWorkService(db);
    await service.saveScheme(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      term: 'First',
      weeks: weeks,
      deleteExistingFirst: true,
    );

    final schemeRows = await (db.select(db.schemeOfWork)).get();
    final lessons = await (db.select(db.lessons)).get();
    // ignore: avoid_print
    print('saveScheme(deleteFirst): schemeRows=${schemeRows.length} '
        'lessons=${lessons.length}');
    expect(schemeRows.length, 13);
    expect(lessons.length, 13);
  });

  group('English Studies JSS1 orphan-draft blocking (reported bug)', () {
    /// Seeds the reported leftover state for English Studies JSS 1 1st Term:
    /// a partial plan (scheme rows for weeks 1-6) plus orphan draft
    /// lessons/exams for weeks 1-6 whose schemeOfWorkId was cleared by the
    /// orphaned-link repair. Orphan lessons block the old duplicate-guard
    /// (weeks 1-6 skipped → only weeks 7-13 appear). Orphan exams are seeded
    /// for parity but must now survive untouched — saveScheme no longer
    /// creates or deletes exams.
    Future<void> seedOrphanBlockers(
      AppDatabase db, {
      required int schoolId,
      required int teacherId,
      required bool withSchemeRows,
    }) async {
      final subjectId = await db.subjectsDao.insert(
        serverId: '00000000-0000-0000-0000-000000000301',
        name: 'English Studies',
        schoolId: '00000000-0000-0000-0000-000000000101',
        sortOrder: 1,
      );
      for (var week = 1; week <= 6; week++) {
        if (withSchemeRows) {
          await db.into(db.schemeOfWork).insert(
                SchemeOfWorkCompanion.insert(
                  schoolId: Value(schoolId),
                  teacherId: Value(teacherId),
                  subjectId: Value(subjectId),
                  term: const Value('First'),
                  weekNumber: Value(week),
                  topic: Value('Stale topic week $week'),
                  objectives: const Value('x'),
                  status: const Value('draft'),
                  classLevel: const Value('JSS 1'),
                ),
              );
        }
        // Orphan draft lesson + exam: unlinked (schemeOfWorkId null), same
        // teacher/class/term/week, with a stale topic.
        await db.into(db.lessons).insert(
              LessonsCompanion.insert(
                subject: 'English Studies',
                classLevel: 'JSS 1',
                week: week,
                topic: 'Stale topic week $week',
                difficulty: 'medium',
                bloomsVerbs: '',
                curriculum: 'NERDC',
                content: '{"objectives":[],"vocabulary":[],"materials":[],"presentation":[],"assessment":"","homework":""}',
                teacherServerId: const Value(
                    '00000000-0000-0000-0000-000000000201'),
                schoolServerId: const Value(
                    '00000000-0000-0000-0000-000000000101'),
                isUnlocked: const Value(false),
                status: const Value('draft'),
                weekNumber: Value(week),
                term: const Value('1st Term'),
              ),
            );
        await db.into(db.exams).insert(
              ExamsCompanion.insert(
                subject: 'English Studies',
                classLevel: 'JSS 1',
                topic: 'Stale topic week $week',
                difficulty: 'medium',
                curriculum: 'NERDC',
                content: '{"mcqs":[],"theory":[],"subjective":[]}',
                teacherServerId: const Value(
                    '00000000-0000-0000-0000-000000000201'),
                schoolServerId: const Value(
                    '00000000-0000-0000-0000-000000000101'),
                isUnlocked: const Value(false),
                weekNumber: Value(week),
                term: const Value('1st Term'),
              ),
            );
      }
    }

    Future<void> assertEnglishPlanFilled(
      AppDatabase db, {
      required bool withSchemeRows,
    }) async {
      final schemeRows = await (db.select(db.schemeOfWork)).get();
      final lessons = await db.lessonsDao.getAll();
      final exams = await db.examsDao.getAll();
      // ignore: avoid_print
      print('English JSS1: schemeRows=${schemeRows.length} '
          'lessons=${lessons.length} exams=${exams.length}');
      expect(schemeRows.length, 13, reason: 'All 13 scheme weeks must exist');
      expect(lessons.length, 13,
          reason: 'All 13 lessons must exist (old skip-guard dropped 1-6)');
      expect(exams.length, 6,
          reason: 'saveScheme never creates exams — only the 6 seeded '
              'orphan exams may exist');
      expect(exams.every((e) => e.topic.startsWith('Stale topic')), isTrue,
          reason: 'Orphan exams must be untouched by plan generation');

      final curated = getNerdcTopics('English Studies', 'JSS 1', '1st Term')!;
      final lessonsByWeek = {
        for (final l in lessons) (l.weekNumber ?? l.week): l,
      };
      for (var week = 1; week <= 13; week++) {
        final lesson = lessonsByWeek[week];
        expect(lesson, isNotNull, reason: 'Lesson for week $week is missing');
        expect(lesson!.topic, curated[week - 1].topic,
            reason: 'Week $week must carry the curated topic, not a stale one');
        expect(lesson.schemeOfWorkId, isNotNull,
            reason: 'Week $week lesson must link to a scheme row');
      }

      // The orphaned leftovers must be soft-deleted (replace path) or fully
      // re-adopted (no-plan path) — never both present with stale topics.
      final stale = lessons
          .where((l) => l.topic.startsWith('Stale topic'))
          .toList();
      expect(stale, isEmpty, reason: 'No stale orphan topics may survive');

      if (withSchemeRows) {
        // Replace path: orphans are soft-deleted, so the raw table has 19
        // lessons (13 live + 6 deleted orphans).
        final allLessons = await (db.select(db.lessons)).get();
        final deletedOrphans = allLessons
            .where((l) => l.isDeleted && l.topic.startsWith('Stale topic'))
            .length;
        expect(deletedOrphans, 6, reason: 'Replace path must soft-delete orphans');
      }
    }

    test('refresh over a partial plan with cleared links fills all 13 weeks',
        () async {
      final db = AppDatabase.forTesting();
      await db.initialize();
      addTearDown(db.close);
      final (schoolId, teacherId) = await _seedAuth(db);
      await seedOrphanBlockers(db,
          schoolId: schoolId, teacherId: teacherId, withSchemeRows: true);

      final topics = getNerdcTopics('English Studies', 'JSS 1', '1st Term')!;
      final weeks = [
        for (var i = 0; i < topics.length; i++)
          {
            'week': i + 1,
            'topic': topics[i].topic,
            'objectives': topics[i].objectives.join('\n'),
          },
      ];

      final service = SchemeOfWorkService(db);
      await service.saveScheme(
        schoolId: schoolId,
        teacherId: teacherId,
        subject: 'English Studies',
        classLevel: 'JSS 1',
        term: 'First',
        weeks: weeks,
        deleteExistingFirst: true,
      );

      await assertEnglishPlanFilled(db, withSchemeRows: true);
    });

    test('fresh generate with orphans but no scheme rows fills all 13 weeks',
        () async {
      final db = AppDatabase.forTesting();
      await db.initialize();
      addTearDown(db.close);
      final (schoolId, teacherId) = await _seedAuth(db);
      await seedOrphanBlockers(db,
          schoolId: schoolId, teacherId: teacherId, withSchemeRows: false);

      final topics = getNerdcTopics('English Studies', 'JSS 1', '1st Term')!;
      final weeks = [
        for (var i = 0; i < topics.length; i++)
          {
            'week': i + 1,
            'topic': topics[i].topic,
            'objectives': topics[i].objectives.join('\n'),
          },
      ];

      final service = SchemeOfWorkService(db);
      // deleteExistingFirst=false — the UI path when findSchemes returns no
      // plan (leftover orphan lessons with no scheme rows).
      await service.saveScheme(
        schoolId: schoolId,
        teacherId: teacherId,
        subject: 'English Studies',
        classLevel: 'JSS 1',
        term: 'First',
        weeks: weeks,
        deleteExistingFirst: false,
      );

      await assertEnglishPlanFilled(db, withSchemeRows: false);
    });
  });
}
