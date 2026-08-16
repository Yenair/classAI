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

/// Mirrors the seeded remote `exam_generation_allowed_tiers` config
/// (`20260815_000001_update_exam_generation_allowed_tiers.sql`) — only
/// Standard and Elite schools may generate exams.
const _defaultAllowedExamTiers = ['standard', 'elite'];

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

/// Defaults to the historical 1/1/1 result so existing tests keep their
/// assertions; callers can request exact per-type counts for hybrid tests.
/// Pass [labelPrefix] (e.g. 'AI') to give the fake's questions distinct
/// labels so they can never collide with saved lesson-question labels.
Future<Map<String, dynamic>> _fakeAiResult({
  int mcqs = 1,
  int theory = 1,
  int subjective = 1,
  String labelPrefix = '',
}) async {
  return {
    'mcqs': [for (var i = 1; i <= mcqs; i++) _mcq(i, labelPrefix: labelPrefix)],
    'theory': [
      for (var i = 1; i <= theory; i++) _theory(i, labelPrefix: labelPrefix),
    ],
    'subjective': [
      for (var i = 1; i <= subjective; i++)
        _subjective(i, labelPrefix: labelPrefix),
    ],
  };
}

Map<String, dynamic> _mcq(int n, {String labelPrefix = ''}) => {
      'question': labelPrefix.isEmpty
          ? 'MCQ question $n'
          : '$labelPrefix MCQ question $n',
      'options': {
        'A': 'Option A $n',
        'B': 'Option B $n',
        'C': 'Option C $n',
        'D': 'Option D $n',
      },
      'correct': 'A',
    };

Map<String, dynamic> _theory(int n, {String labelPrefix = ''}) => {
      'question': labelPrefix.isEmpty
          ? 'Theory question $n'
          : '$labelPrefix Theory question $n',
      'modelAnswer': labelPrefix.isEmpty
          ? 'A complete model answer for theory question $n.'
          : 'A complete model answer for $labelPrefix theory question $n.',
    };

Map<String, dynamic> _subjective(int n, {String labelPrefix = ''}) => {
      'question': labelPrefix.isEmpty
          ? 'Subjective question $n'
          : '$labelPrefix Subjective question $n',
      'answer': labelPrefix.isEmpty
          ? 'A complete answer for subjective question $n.'
          : 'A complete answer for $labelPrefix subjective question $n.',
    };

/// Builds a Phase-2 lesson `content` blob with the given questions.
String _questionsContent({
  List<Map<String, dynamic>> mcqs = const [],
  List<Map<String, dynamic>> theory = const [],
  List<Map<String, dynamic>> subjective = const [],
}) =>
    jsonEncode({
      'questions': {'mcqs': mcqs, 'theory': theory, 'subjective': subjective},
      'attribution': '— Generated for Test Teacher, Test School.',
    });

/// Seeds a lesson row for the teacher/school pair (editor-style rows carry
/// both `week` and `weekNumber`; legacy rows only `week`).
Future<int> _seedLesson(
  AppDatabase db, {
  required String teacherServerId,
  required String schoolServerId,
  required String subject,
  required String classLevel,
  required int week,
  required String topic,
  String? term,
  int? weekNumber,
  String? contentJson,
  DateTime? updatedAt,
}) async {
  final content = contentJson ??
      '{"questions":{"mcqs":[],"theory":[],"subjective":[]}}';
  return db.lessonsDao.insertLesson(
    LessonsCompanion.insert(
      subject: subject,
      classLevel: classLevel,
      week: week,
      topic: topic,
      difficulty: 'medium',
      bloomsVerbs: 'remember, understand, apply',
      curriculum: 'NERDC',
      content: content,
      teacherServerId: Value(teacherServerId),
      schoolServerId: Value(schoolServerId),
      weekNumber: weekNumber != null ? Value(weekNumber) : const Value.absent(),
      term: term != null ? Value(term) : const Value.absent(),
      updatedAt: updatedAt != null ? Value(updatedAt) : const Value.absent(),
    ),
  );
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
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
    // Standard tier limit 12 — a full 13-week run would exceed it.
    await expectLater(
      service.generateWeeklyExams(
        schoolId: fixture.schoolId,
        teacherId: fixture.teacherId,
        teacherServerId: fixture.teacher.serverId!,
        schoolServerId: fixture.school.serverId,
        subscriptionTier: 'standard',
        examGenerationAllowedTiers: _defaultAllowedExamTiers,
        lessonStorageLimits: const {'standard': 12},
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
        subscriptionTier: 'standard',
        examGenerationAllowedTiers: _defaultAllowedExamTiers,
        lessonStorageLimits: const {'standard': 0},
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
    // Standard tier limit 13 — a 13-week run lands exactly at the limit and
    // is still allowed (mirrors the editor: rows up to the limit are OK).
    final count = await service.generateWeeklyExams(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: const {'standard': 13},
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );

    expect(count, 13);
    expect(await db.examsDao.getAll(), hasLength(13));
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), hasLength(13));
  });

  // ── Phase 3 hybrid: saved lesson questions ────────────────────────────

  test('loadSavedLessonQuestions matches subject/class/term/week, picks the '
      'best lesson per week, and flattens in week order', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    // Week 2: two lessons — the older one has more valid questions and must
    // win; the newer regenerated one has fewer.
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 2,
      topic: 'The Eye',
      term: 'First',
      updatedAt: DateTime(2026, 1, 1),
      contentJson: _questionsContent(
        mcqs: [_mcq(1), _mcq(2)],
        theory: [_theory(1)],
      ),
    );
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 2,
      topic: 'Eye (regenerated)',
      term: 'First',
      updatedAt: DateTime(2026, 2, 1),
      contentJson: _questionsContent(mcqs: [_mcq(99)]),
    );
    // Week 3: two lessons with equal question counts — the most recently
    // updated one must win the tie-break.
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 3,
      topic: 'Nervous System (old)',
      term: 'First',
      updatedAt: DateTime(2026, 1, 1),
      contentJson: _questionsContent(mcqs: [_mcq(11)]),
    );
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 3,
      topic: 'Nervous System (new)',
      term: '1st Term',
      updatedAt: DateTime(2026, 2, 1),
      contentJson: _questionsContent(mcqs: [_mcq(12)]),
    );
    // Week 4: legacy row — no weekNumber, empty term (must still match).
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 4,
      topic: 'Digestion',
      contentJson: _questionsContent(mcqs: [_mcq(13)]),
    );
    // Week 5: malformed content — contributes nothing, must not crash.
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 5,
      topic: 'Broken',
      term: 'First',
      contentJson: 'not valid json',
    );
    // Mismatches that must be excluded.
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Mathematics',
      classLevel: 'JSS 3',
      week: 2,
      topic: 'Wrong subject',
      term: 'First',
      contentJson: _questionsContent(mcqs: [_mcq(21)]),
    );
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'SSS 1',
      week: 2,
      topic: 'Wrong class',
      term: 'First',
      contentJson: _questionsContent(mcqs: [_mcq(22)]),
    );
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 2,
      topic: 'Wrong term',
      term: 'Second',
      contentJson: _questionsContent(mcqs: [_mcq(23)]),
    );
    final deletedId = await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 2,
      topic: 'Deleted lesson',
      term: 'First',
      contentJson: _questionsContent(mcqs: [_mcq(24)]),
    );
    await db.lessonsDao.deleteLesson(deletedId);

    final saved = await ExamGenerationService(db).loadSavedLessonQuestions(
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      weekNumbers: [2, 3, 4, 5],
    );

    // W2 (2) + W3-new (1) + W4 legacy (1) + W5 broken (0), in week order.
    expect(saved.mcqs.map((q) => q['question']).toList(), [
      'MCQ question 1',
      'MCQ question 2',
      'MCQ question 12',
      'MCQ question 13',
    ], reason: 'w2 primary wins (more questions), w3 tie-break is newest, '
        'legacy no-term row matches, malformed content contributes nothing');
    expect(saved.theory.map((q) => q['question']).toList(), ['Theory question 1']);
    expect(saved.subjective, isEmpty);
    final texts = saved.mcqs.map((q) => q['question'].toString()).join();
    expect(texts, isNot(contains('99')));
    expect(texts, isNot(contains('21')));
    expect(texts, isNot(contains('22')));
    expect(texts, isNot(contains('23')));
    expect(texts, isNot(contains('24')),
        reason: 'soft-deleted lessons are excluded by getAllForTeacher');
  });

  test('hybrid merge: saved 3 MCQ + 1 Theory for a 3/2/0 request → AI asks '
      'for exactly the remainder and the final exam is complete', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(
        mcqs: [_mcq(1), _mcq(2), _mcq(3)],
        theory: [_theory(1)],
      ),
    );

    final service = ExamGenerationService(db);
    final topics = await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    );
    final topic = topics!.first; // week 1

    String? capturedPrompt;
    final examId = await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topic],
      questionCounts: const [5], // distribute(5) → 3 MCQ + 2 Theory + 0 Subj
      topicTitle: 'Term Exam (1 topic)',
      useSavedLessonQuestions: true,
      aiGenerate: (prompt) async {
        capturedPrompt = prompt;
        // The remainder is exactly 0 MCQ + 1 Theory.
        return _fakeAiResult(mcqs: 0, theory: 1, subjective: 0);
      },
    );

    expect(examId, greaterThan(0));
    expect(capturedPrompt, isNotNull);
    expect(capturedPrompt, contains('Generate 1 Theory questions for Basic '
        'Science'), reason: 'the prompt asks only for the remaining Theory '
        'count');
    expect(capturedPrompt, isNot(contains('2 Theory questions')),
        reason: 'the requested Theory count was reduced from 2 to the '
            'remainder 1');
    expect(capturedPrompt, isNot(contains('3 MCQ questions')),
        reason: 'no MCQs remain after the saved ones');
    expect(capturedPrompt, contains('ALREADY included'),
        reason: 'the do-not-repeat suffix is appended when saved questions '
            'are reused');
    expect(capturedPrompt, contains('MCQ question 1'));
    expect(capturedPrompt, contains('Theory question 1'));

    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(1));
    final content = jsonDecode(exams.single.content) as Map<String, dynamic>;
    expect(content['mcqs'], hasLength(3));
    expect((content['mcqs'] as List).first['question'], 'MCQ question 1',
        reason: 'saved questions come first');
    expect(content['theory'], hasLength(2),
        reason: '1 saved + 1 AI = the requested 2');
    expect(content['subjective'], isEmpty);

    final queue = await db.syncQueueDao.pendingEntries();
    final examQueue = queue.where((e) => e.queueTable == 'exams').toList();
    expect(examQueue, hasLength(1));
    expect(examQueue.single.operation, 'INSERT');
  });

  test('hybrid merge: saved questions exceed the requested count → only the '
      'first requested ones are used, no duplicates', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(
        mcqs: [for (var i = 1; i <= 5; i++) _mcq(i)],
        theory: [_theory(1)],
      ),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    String? capturedPrompt;
    await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topics.first],
      questionCounts: const [5], // → 3 MCQ + 2 Theory + 0 Subj
      topicTitle: 'Term Exam (1 topic)',
      useSavedLessonQuestions: true,
      aiGenerate: (prompt) async {
        capturedPrompt = prompt;
        return _fakeAiResult(mcqs: 0, theory: 1, subjective: 0);
      },
    );

    expect(capturedPrompt, contains('1 Theory questions'),
        reason: '5 saved MCQs cap at the 3 requested — no MCQ remainder');
    expect(capturedPrompt, contains('MCQ question 1'));
    expect(capturedPrompt, contains('MCQ question 3'));
    expect(capturedPrompt, isNot(contains('MCQ question 4')),
        reason: 'only the used (taken) saved questions are listed');

    final content =
        jsonDecode((await db.examsDao.getAll()).single.content) as Map;
    final mcqs = content['mcqs'] as List;
    expect(mcqs, hasLength(3), reason: 'capped at the requested 3, not 5');
    expect(mcqs.map((q) => q['question']).toList(), [
      'MCQ question 1',
      'MCQ question 2',
      'MCQ question 3',
    ]);
    expect(content['theory'], hasLength(2));
    expect(content['subjective'], isEmpty);
  });

  test('hybrid merge: saved questions of an unrequested type are ignored',
      () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(
        mcqs: [_mcq(1), _mcq(2)],
        subjective: [_subjective(1)],
      ),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    String? capturedPrompt;
    await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topics.first],
      questionCounts: const [5], // → 3 MCQ + 2 Theory + 0 Subj
      topicTitle: 'Term Exam (1 topic)',
      useSavedLessonQuestions: true,
      aiGenerate: (prompt) async {
        capturedPrompt = prompt;
        // Remainder after 2 saved MCQs: 1 MCQ + 2 Theory + 0 Subjective.
        return _fakeAiResult(mcqs: 1, theory: 2, subjective: 0);
      },
    );

    expect(capturedPrompt, isNot(contains('Subjective question 1')),
        reason: 'a saved Subjective is never reused in a 0-Subjective exam');
    expect(capturedPrompt, isNot(contains('Subjective questions')),
        reason: 'the AI is asked for 0 Subjective');

    final content =
        jsonDecode((await db.examsDao.getAll()).single.content) as Map;
    expect(content['mcqs'], hasLength(3));
    expect(content['theory'], hasLength(2));
    expect(content['subjective'], isEmpty,
        reason: 'the saved Subjective question must not leak into the exam');
  });

  test('fully covered by saved questions: aiGenerate is never invoked and '
      'the exam is written complete', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(
        mcqs: [_mcq(1), _mcq(2), _mcq(3)],
        theory: [_theory(1), _theory(2)],
      ),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    var aiCalled = false;
    String? capturedPrompt;
    final examId = await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topics.first],
      questionCounts: const [5], // → 3 MCQ + 2 Theory, all covered
      topicTitle: 'Term Exam (1 topic)',
      useSavedLessonQuestions: true,
      aiGenerate: (prompt) async {
        aiCalled = true;
        capturedPrompt = prompt;
        return _fakeAiResult();
      },
    );

    expect(examId, greaterThan(0));
    expect(aiCalled, isFalse,
        reason: 'the AI call must be skipped entirely when all remaining '
            'counts are 0 (approved additional rule)');
    expect(capturedPrompt, isNull);

    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(1));
    final content = jsonDecode(exams.single.content) as Map<String, dynamic>;
    expect(content['mcqs'], hasLength(3));
    expect(content['theory'], hasLength(2));
    expect(content['subjective'], isEmpty);

    final queue = await db.syncQueueDao.pendingEntries();
    final examQueue = queue.where((e) => e.queueTable == 'exams').toList();
    expect(examQueue, hasLength(1));
    expect(examQueue.single.operation, 'INSERT');
  });

  test('AI shortfall: throws ExamIncompleteGenerationException and creates '
      'zero rows and zero queue entries', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(
        mcqs: [_mcq(1), _mcq(2)],
        theory: [_theory(1)],
      ),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    await expectLater(
      service.generateCombinedExam(
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        termLabel: '1st Term',
        teacherServerId: teacherServerId,
        schoolServerId: schoolServerId,
        subscriptionTier: 'standard',
        examGenerationAllowedTiers: _defaultAllowedExamTiers,
        lessonStorageLimits: _defaultStorageLimits,
        difficulty: 'medium',
        topics: [topics.first],
        questionCounts: const [5], // remainder: 1 MCQ + 1 Theory
        topicTitle: 'Term Exam (1 topic)',
        useSavedLessonQuestions: true,
        aiGenerate: (prompt) async =>
            _fakeAiResult(mcqs: 1, theory: 0, subjective: 0),
      ),
      throwsA(isA<ExamIncompleteGenerationException>()),
    );

    expect(await db.examsDao.getAll(), isEmpty,
        reason: 'no partial exam may persist');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), isEmpty,
        reason: 'no sync entry may be queued for an incomplete exam');
  });

  test('AI failure: the exception propagates and leaves zero rows and zero '
      'queue entries', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(mcqs: [_mcq(1)]),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    await expectLater(
      service.generateCombinedExam(
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        termLabel: '1st Term',
        teacherServerId: teacherServerId,
        schoolServerId: schoolServerId,
        subscriptionTier: 'standard',
        examGenerationAllowedTiers: _defaultAllowedExamTiers,
        lessonStorageLimits: _defaultStorageLimits,
        difficulty: 'medium',
        topics: [topics.first],
        questionCounts: const [5],
        topicTitle: 'Term Exam (1 topic)',
        useSavedLessonQuestions: true,
        aiGenerate: (prompt) async => throw StateError('AI is down'),
      ),
      throwsA(isA<StateError>()),
    );

    expect(await db.examsDao.getAll(), isEmpty,
        reason: 'the row is only inserted after the AI call succeeds');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), isEmpty,
        reason: 'no partial exam with just the saved questions may persist');
  });

  test('unchecked checkbox: useSavedLessonQuestions false is byte-identical '
      'to the pure-AI path (no merge, no fill check)', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    // Saved questions exist but the checkbox is off — they must be ignored.
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(
        mcqs: [_mcq(1), _mcq(2), _mcq(3)],
        theory: [_theory(1)],
      ),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    var aiCalls = 0;
    String? capturedPrompt;
    await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topics.first],
      questionCounts: const [5], // pure-AI prompt still asks for 3/2/0
      topicTitle: 'Term Exam (1 topic)',
      useSavedLessonQuestions: false,
      aiGenerate: (prompt) async {
        aiCalls++;
        capturedPrompt = prompt;
        return _fakeAiResult(); // returns 1/1/1 — today's lenient behavior
      },
    );

    expect(aiCalls, 1, reason: 'exactly one AI call, no fill-check loop');
    expect(capturedPrompt, contains('3 MCQ questions'));
    expect(capturedPrompt, contains('2 Theory questions'));
    expect(capturedPrompt, isNot(contains('ALREADY included')),
        reason: 'no do-not-repeat suffix when saved questions are unused');

    final content =
        jsonDecode((await db.examsDao.getAll()).single.content) as Map;
    expect(content['mcqs'], hasLength(1));
    expect(content['theory'], hasLength(1));
    expect(content['subjective'], hasLength(1));
  });

  test('quota still wins with useSavedLessonQuestions: storage-limit throws '
      'before any AI call, zero rows and zero queue entries', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(
        mcqs: [_mcq(1), _mcq(2), _mcq(3)],
        theory: [_theory(1), _theory(2)],
      ),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    var aiCalled = false;
    await expectLater(
      service.generateCombinedExam(
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        termLabel: '1st Term',
        teacherServerId: teacherServerId,
        schoolServerId: schoolServerId,
        subscriptionTier: 'standard',
        examGenerationAllowedTiers: _defaultAllowedExamTiers,
        lessonStorageLimits: const {'standard': 0},
        difficulty: 'medium',
        topics: [topics.first],
        questionCounts: const [5],
        topicTitle: 'Term Exam (1 topic)',
        useSavedLessonQuestions: true,
        aiGenerate: (prompt) async {
          aiCalled = true;
          return _fakeAiResult();
        },
      ),
      throwsA(isA<ExamStorageLimitExceededException>()),
    );

    expect(aiCalled, isFalse,
        reason: 'quota failure happens before the hybrid lookup and AI call');
    expect(await db.examsDao.getAll(), isEmpty);
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), isEmpty);
  });

  test('hybrid merge: AI returning more than the remainder is capped so the '
      'final exam never exceeds the requested totals', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);
    final teacherServerId = fixture.teacher.serverId!;
    final schoolServerId = fixture.school.serverId!;

    // 2 saved MCQs; topic count 10 → requested 5 MCQ + 3 Theory + 2 Subj, so
    // the MCQ remainder is 3.
    await _seedLesson(
      db,
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      week: 1,
      topic: 'The Eye',
      term: 'First',
      contentJson: _questionsContent(mcqs: [_mcq(1), _mcq(2)]),
    );

    final service = ExamGenerationService(db);
    final topics = (await service.loadTermTopics(
      schoolId: fixture.schoolId,
      teacherId: fixture.teacherId,
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
    ))!;

    String? capturedPrompt;
    await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: teacherServerId,
      schoolServerId: schoolServerId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topics.first],
      questionCounts: const [10], // distribute(10) → 5 MCQ + 3 Theory + 2 Subj
      topicTitle: 'Term Exam (1 topic)',
      useSavedLessonQuestions: true,
      aiGenerate: (prompt) async {
        capturedPrompt = prompt;
        // The AI overshoots MCQs (5 returned for a 3-MCQ remainder) and
        // returns exactly the Theory/Subjective remainders. 'AI' prefix
        // keeps the fake's labels distinct from the 2 saved MCQs so the
        // cap is asserted on distinct questions.
        return _fakeAiResult(
          mcqs: 5,
          theory: 3,
          subjective: 2,
          labelPrefix: 'AI',
        );
      },
    );

    expect(capturedPrompt, contains('3 MCQ questions'),
        reason: 'the prompt asks only for the 3-MCQ remainder');
    expect(capturedPrompt, isNot(contains('5 MCQ questions')),
        reason: 'the prompt must not ask for more MCQs than the remainder');

    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(1));
    final content = jsonDecode(exams.single.content) as Map;
    final mcqs = content['mcqs'] as List;
    expect(mcqs, hasLength(5),
        reason: '2 saved + 3 capped AI = exactly the requested 5, no '
            'overshoot');
    expect(mcqs.map((q) => q['question']).toList(), [
      'MCQ question 1', // saved lesson question
      'MCQ question 2', // saved lesson question
      'AI MCQ question 1', // AI, capped to the 3-MCQ remainder
      'AI MCQ question 2',
      'AI MCQ question 3',
    ], reason: 'saved questions come first, then exactly the capped AI '
        'remainder — 5 total, never more');
    expect(content['theory'], hasLength(3));
    expect(content['subjective'], hasLength(2));

    final queue = await db.syncQueueDao.pendingEntries();
    final examQueue = queue.where((e) => e.queueTable == 'exams').toList();
    expect(examQueue, hasLength(1));
    expect(examQueue.single.operation, 'INSERT');
  });

  // ── Phase 4: subscription-tier gating ─────────────────────────────────

  test('generateWeeklyExams with a Basic school throws '
      'ExamGenerationNotAllowedException and creates nothing', () async {
    final db = AppDatabase.forTesting();
    await db.initialize();
    addTearDown(db.close);
    final fixture = await _seedAuth(db);

    final service = ExamGenerationService(db);
    await expectLater(
      service.generateWeeklyExams(
        schoolId: fixture.schoolId,
        teacherId: fixture.teacherId,
        teacherServerId: fixture.teacher.serverId!,
        schoolServerId: fixture.school.serverId,
        subscriptionTier: 'basic',
        examGenerationAllowedTiers: _defaultAllowedExamTiers,
        lessonStorageLimits: _defaultStorageLimits,
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        termLabel: '1st Term',
      ),
      throwsA(isA<ExamGenerationNotAllowedException>()),
    );

    expect(await db.examsDao.getAll(), isEmpty,
        reason: 'the tier gate must not create exam rows');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), isEmpty,
        reason: 'the tier gate must not queue sync entries');
  });

  test('generateCombinedExam with a Basic school throws, never calls AI and '
      'creates nothing', () async {
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
    await expectLater(
      service.generateCombinedExam(
        subject: 'Basic Science',
        classLevel: 'JSS 3',
        termLabel: '1st Term',
        teacherServerId: fixture.teacher.serverId!,
        schoolServerId: fixture.school.serverId,
        subscriptionTier: 'basic',
        examGenerationAllowedTiers: _defaultAllowedExamTiers,
        lessonStorageLimits: _defaultStorageLimits,
        difficulty: 'medium',
        topics: topics,
        questionCounts: List.filled(topics.length, 5),
        topicTitle: 'Term Exam (13 topics)',
        aiGenerate: (prompt) async {
          aiCalled = true;
          return _fakeAiResult();
        },
      ),
      throwsA(isA<ExamGenerationNotAllowedException>()),
    );

    expect(aiCalled, isFalse,
        reason: 'the tier gate must fire before any AI call');
    expect(await db.examsDao.getAll(), isEmpty,
        reason: 'the tier gate must not create exam rows');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), isEmpty,
        reason: 'the tier gate must not queue sync entries');
  });

  test('generateCombinedExam with an Elite school still works (elite is in '
      'the allowed tiers)', () async {
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

    final examId = await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'elite',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topics.first],
      questionCounts: const [5],
      topicTitle: 'Term Exam (1 topic)',
      aiGenerate: (prompt) async => _fakeAiResult(),
    );

    expect(examId, greaterThan(0),
        reason: 'elite is allowed — generation must succeed');
    expect(await db.examsDao.getAll(), hasLength(1));
  });

  test('malformed AI content in generateCombinedExam does not crash — '
      'non-list and non-map entries fall back to safe empty output',
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

    final examId = await service.generateCombinedExam(
      subject: 'Basic Science',
      classLevel: 'JSS 3',
      termLabel: '1st Term',
      teacherServerId: fixture.teacher.serverId!,
      schoolServerId: fixture.school.serverId,
      subscriptionTier: 'standard',
      examGenerationAllowedTiers: _defaultAllowedExamTiers,
      lessonStorageLimits: _defaultStorageLimits,
      difficulty: 'medium',
      topics: [topics.first],
      questionCounts: const [5],
      topicTitle: 'Term Exam (1 topic)',
      aiGenerate: (prompt) async => {
        'mcqs': 'not a list at all',
        'theory': [_theory(1), 'garbage', 42],
        'subjective': null,
      },
    );

    expect(examId, greaterThan(0),
        reason: 'malformed AI output must never crash the service');
    final exams = await db.examsDao.getAll();
    expect(exams, hasLength(1));
    final content = jsonDecode(exams.single.content) as Map<String, dynamic>;
    expect(content['mcqs'], isEmpty,
        reason: 'a non-list value contributes no questions');
    expect(content['theory'], hasLength(1),
        reason: 'non-map entries are dropped, valid maps survive');
    expect(content['subjective'], isEmpty,
        reason: 'null contributes no questions');
    final queue = await db.syncQueueDao.pendingEntries();
    expect(queue.where((e) => e.queueTable == 'exams'), hasLength(1));
  });
}
