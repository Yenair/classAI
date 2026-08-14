import 'dart:convert';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/exam_generation_service.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

/// Mirrors the seeded remote `lesson_storage_limits` config
/// (`20260711_115003_add_premium_limits.sql`).
const _defaultStorageLimits = <String, int>{
  'free': 10,
  'basic': 20,
  'standard': 50,
  'elite': -1,
};

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

Future<_AuthFixture> _seedAuth(AppDatabase db) async {
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

/// Seeds a subject row + one scheme_of_work row for the given combo and
/// returns the scheme row id.
Future<int> _seedSchemeWeek(
  AppDatabase db, {
  required int schoolId,
  required int teacherId,
  required String subject,
  required String classLevel,
  required String termStorage,
  required int weekNumber,
  required String topic,
}) async {
  // Resolve the subject by name and reuse the existing row (mirroring
  // SchemeOfWorkService._resolveOrInsertSubjectId) so every week of a plan
  // links to the SAME subject row. Inserting a fresh subject per week would
  // split the scheme rows across two subject ids with the same name, and
  // SchemeOfWorkService.findSchemes joins on a single resolved subjectId —
  // only the first week's row would ever match.
  final school = await db.schoolsDao.getByLocalId(schoolId);
  final schoolServerId = school?.serverId;
  final existingSubject = schoolServerId != null
      ? await db.subjectsDao.getByNameAndSchool(subject, schoolServerId)
      : await db.subjectsDao.getByName(subject);
  final subjectId = existingSubject?.id ??
      await db.subjectsDao.insert(
        serverId: '00000000-0000-0000-0000-000000000301',
        name: subject,
        schoolId: '00000000-0000-0000-0000-000000000101',
        sortOrder: 1,
      );
  return db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          schoolId: Value(schoolId),
          teacherId: Value(teacherId),
          subjectId: Value(subjectId),
          term: Value(termStorage),
          weekNumber: Value(weekNumber),
          topic: Value(topic),
          objectives: const Value('x'),
          status: const Value('draft'),
          classLevel: Value(classLevel),
        ),
      );
}

Future<Map<String, dynamic>> _fakeAiResult() async {
  return {
    'mcqs': [
      {
        'question': 'What is 2+2?',
        'options': {'A': '2', 'B': '3', 'C': '4', 'D': '5'},
        'correct': 'C',
      },
    ],
    'theory': [
      {'question': 'Explain fractions', 'modelAnswer': 'Fractions are parts of a whole.'},
    ],
    'subjective': [
      {'question': 'Describe your school', 'answer': 'My school is large.', 'rubric': 'Clarity'},
    ],
  };
}

void main() {
  test('saveScheme queues lessons and scheme rows but never exams', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    await SchemeOfWorkService(db).saveScheme(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      term: 'First',
      weeks: [
        {'week': 1, 'topic': 'Nervous System', 'objectives': 'x'},
        {'week': 2, 'topic': 'The Eye', 'objectives': 'y'},
      ],
    );

    final pending = await db.syncQueueDao.pendingEntries();
    final tables = pending.map((e) => e.queueTable).toSet();
    expect(tables, contains('scheme_of_work'));
    expect(tables, contains('lessons'));
    expect(tables, isNot(contains('exams')),
        reason: 'saveScheme must never queue exam creation');
    expect(await db.examsDao.getAll(), isEmpty,
        reason: 'saveScheme must never create draft exams');
  });

  test('saveScheme deleteExistingFirst never creates or deletes exams',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    // Seed a 1-week plan + an exam linked to it.
    final schemeId = await _seedSchemeWeek(
      db,
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termStorage: 'First',
      weekNumber: 1,
      topic: 'Nervous System',
    );
    await db.examsDao.insertExam(
      ExamsCompanion.insert(
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        topic: 'Nervous System',
        difficulty: 'medium',
        curriculum: 'NERDC',
        content: '{"mcqs":[],"theory":[],"subjective":[]}',
        teacherServerId:
            const Value('00000000-0000-0000-0000-000000000201'),
        schoolServerId:
            const Value('00000000-0000-0000-0000-000000000101'),
        isUnlocked: const Value(false),
        schemeOfWorkId: Value(schemeId.toString()),
        weekNumber: const Value(1),
        term: const Value('1st Term'),
      ),
    );

    await SchemeOfWorkService(db).saveScheme(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      term: 'First',
      weeks: [
        {'week': 1, 'topic': 'Nervous System', 'objectives': 'x'},
      ],
      deleteExistingFirst: true,
    );

    // The plan was replaced but the exam survives untouched — exams are no
    // longer tied to the plan lifecycle.
    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(1));
    expect(exams.single.topic, 'Nervous System');
    expect(exams.single.isDeleted, isFalse);
  });

  test('generateWeeklyExams creates 13 exam rows and queues 13 exams INSERTs',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    final count = await service.generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );

    expect(count, 13);
    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(13));
    expect(exams.map((e) => e.weekNumber).toSet(), {for (var w = 1; w <= 13; w++) w});
    expect(exams.every((e) => !e.isUnlocked), isTrue,
        reason: 'weekly drafts must start locked');
    expect(exams.every((e) => e.term == '1st Term'), isTrue);
    for (final exam in exams) {
      final content = jsonDecode(exam.content) as Map<String, dynamic>;
      expect(content['mcqs'], isEmpty);
      expect(content['theory'], isEmpty);
      expect(content['subjective'], isEmpty);
    }

    final queue = await db.syncQueueDao.pendingEntries();
    final examQueue = queue.where((e) => e.queueTable == 'exams').toList();
    expect(examQueue, hasLength(13));
    expect(examQueue.every((e) => e.operation == 'INSERT'), isTrue);
    for (final entry in examQueue) {
      final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
      expect(payload['subject'], 'Basic Science');
      expect(payload['classLevel'], 'JSS 3',
          reason: 'payload shape mirrors the exam editor save path');
      expect(payload['is_unlocked'], false);
      expect(payload['week_number'], isA<int>());
      expect(payload['term'], '1st Term');
    }
  });

  test('generateWeeklyExams does not create lessons or scheme rows', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    await ExamGenerationService(db).generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );

    expect(await db.lessonsDao.getAll(), isEmpty,
        reason: 'weekly exam generation must not create lessons');
    expect(await (db.select(db.schemeOfWork)).get(), isEmpty,
        reason: 'weekly exam generation must not create scheme rows');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'lessons'), isEmpty);
    expect(queue.where((e) => e.queueTable == 'scheme_of_work'), isEmpty);
  });

  test('generateWeeklyExams is duplicate-safe when run twice', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    await service.generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );
    await service.generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );

    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(13),
        reason: 'the second run must reuse the existing weekly drafts, not '
            'duplicate them');
  });

  test('generateWeeklyExams uses matching scheme week topics first', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    await _seedSchemeWeek(
      db,
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termStorage: 'First',
      weekNumber: 1,
      topic: 'Custom Week 1 Topic',
    );
    await _seedSchemeWeek(
      db,
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termStorage: 'First',
      weekNumber: 2,
      topic: 'Custom Week 2 Topic',
    );

    final count = await ExamGenerationService(db).generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );

    expect(count, 2,
        reason: 'only the scheme weeks exist — no curated topics are added');
    final exams = await db.examsDao.getAll();
    expect(exams.map((e) => e.topic).toSet(),
        {'Custom Week 1 Topic', 'Custom Week 2 Topic'});
    expect(exams.every((e) => e.schemeOfWorkId != null), isTrue,
        reason: 'drafts for scheme weeks must be linked to the scheme rows');
  });

  test('loadTermTopics returns null when no scheme/NERDC/AI topics exist',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final topics = await ExamGenerationService(db).loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Quantum Basket Weaving',
      classLevel: 'JSS 1',
      termLabel: '1st Term',
    );
    expect(topics, isNull);
  });

  test('Term Exam mode creates one combined exam from all term topics',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    final topics = await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );
    expect(topics, isNotNull);
    expect(topics!.length, 13);

    String? capturedPrompt;
    final examId = await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: topics,
      questionCounts: List.filled(topics.length, 5),
      topicTitle: 'Term Exam (13 topics)',
      aiGenerate: (prompt) async {
        capturedPrompt = prompt;
        return _fakeAiResult();
      },
    );

    expect(examId, greaterThan(0));
    expect(capturedPrompt, isNotNull);
    expect(capturedPrompt, contains('Basic Science'));
    expect(capturedPrompt, contains('- Week 1:'));
    expect(capturedPrompt, contains('- Week 13:'));

    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(1), reason: 'exactly ONE combined exam row');
    expect(exams.single.topic, 'Term Exam (13 topics)');
    expect(exams.single.subject, 'Basic Science');
    expect(exams.single.classLevel, 'JSS 3');
    expect(exams.single.term, '1st Term');
    expect(exams.single.weekNumber, 1);
    final content = jsonDecode(exams.single.content) as Map<String, dynamic>;
    expect(content['mcqs'], hasLength(1));
    expect(content['theory'], hasLength(1));
    expect(content['subjective'], hasLength(1));

    final queue = await db.syncQueueDao.pendingEntries();
    final examQueue = queue.where((e) => e.queueTable == 'exams').toList();
    expect(examQueue, hasLength(1));
    expect(examQueue.single.operation, 'INSERT');
  });

  test('CA Test mode creates one combined exam from only ticked topics',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    // Teacher ticks only weeks 2, 5 and 9.
    final ticked = [topics[1], topics[4], topics[8]];
    String? capturedPrompt;
    final examId = await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: ticked,
      questionCounts: const [5, 5, 5],
      topicTitle: 'CA Test (3 topics)',
      aiGenerate: (prompt) async {
        capturedPrompt = prompt;
        return _fakeAiResult();
      },
    );

    expect(examId, greaterThan(0));
    expect(capturedPrompt, isNotNull);
    expect(capturedPrompt, contains('- Week 2:'));
    expect(capturedPrompt, contains('- Week 5:'));
    expect(capturedPrompt, contains('- Week 9:'));
    expect(capturedPrompt, isNot(contains('- Week 1:')),
        reason: 'unticked topics must not reach the AI prompt');

    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(1), reason: 'exactly ONE combined exam row');
    expect(exams.single.topic, 'CA Test (3 topics)');
  });

  test('generateWeeklyExams falls back to AI scheme topics when no curated '
      'topics exist', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    String? capturedPrompt;
    final count = await ExamGenerationService(db).generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      lessonStorageLimits: _defaultStorageLimits,
      subject: 'Quantum Basket Weaving',
      classLevel: 'JSS 1',
      termLabel: '1st Term',
      aiGenerate: (prompt) async {
        capturedPrompt = prompt;
        return {
          'weeks': [
            for (var w = 1; w <= 13; w++)
              {'week': w, 'topic': 'AI topic week $w', 'objectives': ['o']},
          ],
        };
      },
    );

    expect(capturedPrompt, isNotNull);
    expect(capturedPrompt, contains('Quantum Basket Weaving'));
    expect(count, 13);
    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(13));
    expect(exams.first.topic, 'AI topic week 1');
  });

  test('generateWeeklyExams quota exceeded: throws, creates zero rows and '
      'zero queue entries', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    // Basic tier limit 12 — a full 13-week run would exceed it.
    await expectLater(
      service.generateWeeklyExams(
        schoolId: fixture.schoolId,
        teacherId: fixture.teacherId,
        teacherServerId: fixture.teacher.serverId!,
        schoolServerId: fixture.school.serverId,
        subscriptionTier: 'basic',
        lessonStorageLimits: const {'basic': 12},
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        termLabel: '1st Term',
      ),
      throwsA(isA<ExamStorageLimitExceededException>()),
    );

    expect(await db.examsDao.getAll(), isEmpty,
        reason: 'quota failure must not create exam rows');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), isEmpty,
        reason: 'quota failure must not queue sync entries');
  });

  test('generateCombinedExam quota exceeded: throws before the AI call and '
      'creates zero rows / zero queue entries', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    var aiCalled = false;
    // Limit 0 — the school is already at capacity, so even one new row fails
    // before the AI prompt is issued.
    await expectLater(
      service.generateCombinedExam(
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        termLabel: '1st Term',
        teacherServerId: fixture.teacher.serverId!,
        schoolServerId: fixture.school.serverId,
        subscriptionTier: 'basic',
        lessonStorageLimits: const {'basic': 0},
        difficulty: 'medium',
        topics: topics,
        questionCounts: List.filled(topics.length, 5),
        topicTitle: 'Term Exam (13 topics)',
        aiGenerate: (prompt) async {
          aiCalled = true;
          return _fakeAiResult();
        },
      ),
      throwsA(isA<ExamStorageLimitExceededException>()),
    );

    expect(aiCalled, isFalse,
        reason: 'quota failure must happen before the AI call');
    expect(await db.examsDao.getAll(), isEmpty,
        reason: 'quota failure must not create exam rows');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), isEmpty,
        reason: 'quota failure must not queue sync entries');
  });

  test('generateWeeklyExams succeeds when the run stays within the storage '
      'limit', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    // Basic tier limit 13 — a 13-week run lands exactly at the limit and is
    // still allowed (mirrors the editor: rows up to the limit are OK).
    final count = await service.generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'basic',
      lessonStorageLimits: const {'basic': 13},
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );

    expect(count, 13);
    expect(await db.examsDao.getAll(), hasLength(13));
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), hasLength(13));
  });
}
