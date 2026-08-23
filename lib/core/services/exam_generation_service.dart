// lib/core/services/exam_generation_service.dart
import 'dart:convert';
import 'dart:math' show min;

import 'package:drift/drift.dart' show Value;
import 'package:classai/core/constants/prompt_templates.dart';
import 'package:classai/core/data/nerdc_curriculum.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/question_validation.dart';
import 'package:classai/core/services/scheme_of_work_service.dart';

/// Thrown when no topics can be resolved for a subject/class/term (no
/// matching scheme rows, no curated NERDC topics, and the AI fallback was
/// unavailable or returned nothing).
class ExamTopicsUnavailableException implements Exception {
  const ExamTopicsUnavailableException();

  @override
  String toString() =>
      'No topics are available for this subject, class and term. '
      'Check your internet connection and try again.';
}

/// Thrown when a combined exam has no topics/questions to generate.
class ExamGenerationEmptySelectionException implements Exception {
  const ExamGenerationEmptySelectionException();

  @override
  String toString() => 'Select at least one topic to generate.';
}

/// Thrown when creating exams would exceed the school's per-tier exam storage
/// limit — the same `lesson_storage_limits` rule the exam editor enforces in
/// `_saveExam` before inserting a new exam. Nothing is created or queued when
/// this is thrown.
class ExamStorageLimitExceededException implements Exception {
  const ExamStorageLimitExceededException();

  @override
  String toString() =>
      'Exam storage limit reached. Upgrade your school plan to create more '
      'exams.';
}

/// Thrown when the school's subscription tier is not in the configured
/// `exam_generation_allowed_tiers` (only Standard and Elite). Thrown at the
/// very start of generation — before any DB insert, AI call or quota check —
/// so nothing is ever created or queued for a disallowed tier.
class ExamGenerationNotAllowedException implements Exception {
  const ExamGenerationNotAllowedException();

  @override
  String toString() =>
      'Exam generation is only available on Standard and Elite plans. '
      'Upgrade to generate exams.';
}

/// Thrown when the hybrid merge cannot reach the requested per-type question
/// counts even after the AI fill — nothing is created or queued, so no
/// partial exam can ever persist.
class ExamIncompleteGenerationException implements Exception {
  const ExamIncompleteGenerationException(this.missing);

  /// Type → how many questions are still missing.
  final Map<String, int> missing;

  @override
  String toString() =>
      'AI could not complete the exam (still missing $missing). '
      'No exam was created — try again.';
}

/// One week's topic for a term exam / CA test generation.
class TermTopic {
  final int weekNumber;
  final String topic;

  /// Local scheme_of_work row id, set only when a matching saved plan exists.
  final int? schemeOfWorkId;

  const TermTopic({
    required this.weekNumber,
    required this.topic,
    this.schemeOfWorkId,
  });
}

/// Aggregated, validated saved lesson questions for a set of weeks,
/// flattened in ascending week order.
class SavedLessonQuestions {
  final List<Map<String, dynamic>> mcqs;
  final List<Map<String, dynamic>> theory;
  final List<Map<String, dynamic>> subjective;

  const SavedLessonQuestions({
    required this.mcqs,
    required this.theory,
    required this.subjective,
  });

  const SavedLessonQuestions.empty()
      : mcqs = const [],
        theory = const [],
        subjective = const [];

  int get total => mcqs.length + theory.length + subjective.length;
}

/// Safely normalizes AI-returned question lists (any of the accepted keys)
/// into `List<Map<String, dynamic>>`: non-list values contribute nothing,
/// non-map entries are dropped and each map is copied, so the result is
/// never a lazy cast view and malformed AI output cannot crash the app.
List<Map<String, dynamic>> castQuestions(dynamic value) {
  if (value is! List) return const [];
  return value
      .whereType<Map>()
      .map((m) => Map<String, dynamic>.from(m))
      .toList();
}

/// Shared persistence + generation for the explicit exam-creation flows:
/// `loadTermTopics` + `generateCombinedExam` — ONE combined exam from all
/// term topics (Term Exam) or only the ticked topics (CA Test).
///
/// This service is the single place that creates exam rows on behalf of the
/// Exams list and the exam editor's combined mode, so there is exactly one
/// payload shape for the `exams` sync queue (mirroring the editor save path).
class ExamGenerationService {
  final AppDatabase db;
  ExamGenerationService(this.db);

  /// Resolves the topics for a subject/class/term in priority order:
  ///
  /// 1. Matching local scheme of work rows (week order) when a saved plan
  ///    exists for the combo — their week topics are used as-is and the
  ///    returned [TermTopic]s carry the scheme row id so created exams can be
  ///    linked.
  /// 2. Curated NERDC topics via [getNerdcTopics] when the combo is covered.
  /// 3. AI fallback via [PromptTemplates.schemeOfWork] +
  ///    [parseSchemeWeeks] when [aiGenerate] is provided.
  ///
  /// Returns null only when all three sources fail (the caller then shows a
  /// clear message and does nothing).
  Future<List<TermTopic>?> loadTermTopics({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String termLabel,
    Future<Map<String, dynamic>> Function(String prompt)? aiGenerate,
  }) async {
    // 1. Matching local scheme rows, in week order.
    final schemes = await SchemeOfWorkService(db).findSchemes(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: subject,
      classLevel: classLevel,
      term: termLabel,
    );
    if (schemes.isNotEmpty) {
      final sorted = List<SchemeOfWorkData>.from(schemes)
        ..sort((a, b) => a.weekNumber.compareTo(b.weekNumber));
      return [
        for (final scheme in sorted)
          TermTopic(
            weekNumber: scheme.weekNumber,
            topic: scheme.adminEditedTopic ?? scheme.topic,
            schemeOfWorkId: scheme.id,
          ),
      ];
    }

    // 2. Curated NERDC topics (13 weeks, week = index + 1).
    final curated = getNerdcTopics(subject, classLevel, termLabel);
    if (curated != null && curated.isNotEmpty) {
      return [
        for (var i = 0; i < curated.length; i++)
          TermTopic(weekNumber: i + 1, topic: curated[i].topic),
      ];
    }

    // 3. AI fallback (scheme topics only — never creates scheme rows).
    if (aiGenerate != null) {
      final prompt = PromptTemplates.schemeOfWork(subject, classLevel, termLabel);
      final result = await aiGenerate(prompt);
      final weeks = parseSchemeWeeks(result);
      if (weeks.isNotEmpty) {
        return [
          for (var i = 0; i < weeks.length; i++)
            TermTopic(
              weekNumber: (weeks[i]['week'] as int?) ?? (i + 1),
              topic: weeks[i]['topic']?.toString().trim() ?? '',
            ),
        ];
      }
    }

    return null;
  }

  /// Generates ONE combined exam from [topics] with the parallel
  /// [questionCounts] (entries with count <= 0 are skipped), using the
  /// multi-topic [PromptTemplates.examQuestions] prompt via [aiGenerate].
  ///
  /// The prompt/parse/save logic is moved from the old Full-Term Exam screen:
  /// question totals are distributed across MCQ (50%), Theory (30%) and
  /// Subjective (the remainder), the AI result is parsed into the exam
  /// content shape (`mcqs`/`theory`/`subjective`), and ONE exam row is
  /// inserted with a single `exams` INSERT sync entry.
  ///
  /// [topicTitle] is the exam's display topic, e.g. "Term Exam (13 topics)".
  /// Returns the new exam's local id.
  Future<int> generateCombinedExam({
    required String subject,
    required String classLevel,
    required String termLabel,
    required String teacherServerId,
    required String? schoolServerId,

    /// The school's subscription tier (lowercase) and the remote
    /// `lesson_storage_limits` map used to enforce the per-tier exam storage
    /// quota — the same inputs the exam editor's `_saveExam` guard reads.
    required String subscriptionTier,

    /// Remote `exam_generation_allowed_tiers` config (lowercased). The school
    /// must be in this list or [ExamGenerationNotAllowedException] is thrown
    /// before anything is loaded, checked, written or queued.
    required List<String> examGenerationAllowedTiers,

    required Map<String, dynamic> lessonStorageLimits,

    required String difficulty,
    required List<TermTopic> topics,
    required List<int> questionCounts,
    required String topicTitle,
    required Future<Map<String, dynamic>> Function(String prompt) aiGenerate,
    /// Phase 3: reuse saved lesson questions first; AI fills the remainder.
    /// Never produces a partial exam — throws ExamIncompleteGenerationException
    /// (or the AI failure itself) before anything is inserted or queued.
    /// When every requested question is covered by saved lessons, [aiGenerate]
    /// is not called at all and the exam is built from saved questions only.
    bool useSavedLessonQuestions = false,
    String teacherName = 'Teacher',
    String schoolName = 'School',
  }) async {
    // Subscription-tier gate — before ANY DB read/write, AI call or quota
    // check. Only Standard and Elite may generate exams.
    if (!examGenerationAllowedTiers.contains(subscriptionTier.toLowerCase())) {
      throw const ExamGenerationNotAllowedException();
    }

    if (topics.isEmpty) {
      throw const ExamGenerationEmptySelectionException();
    }

    // Storage quota guard — the same per-tier `lesson_storage_limits` rule the
    // exam editor enforces before inserting a new exam. ONE row is created, so
    // fail before the AI call when the school is already at its limit.
    await _ensureWithinStorageLimit(
      schoolServerId: schoolServerId,
      subscriptionTier: subscriptionTier,
      lessonStorageLimits: lessonStorageLimits,
      newRowCount: 1,
    );

    // Build the multi-topic prompt + distribute counts across question types.
    final topicParts = <String>[];
    var totalMcq = 0;
    var totalTheory = 0;
    var totalSubjective = 0;
    for (var i = 0; i < topics.length; i++) {
      final count = questionCounts[i];
      if (count <= 0) continue;
      topicParts.add(
        '- Week ${topics[i].weekNumber}: "${topics[i].topic}" '
        '($count questions)',
      );
      final (mcq, theory, subjective) = distributePerTopicCount(count);
      totalMcq += mcq;
      totalTheory += theory;
      totalSubjective += subjective;
    }
    if (topicParts.isEmpty) {
      throw const ExamGenerationEmptySelectionException();
    }

    var typeCounts = <String, int>{
      'MCQ': totalMcq,
      'Theory': totalTheory,
      'Subjective': totalSubjective,
    };

    // Phase 3 hybrid: reuse saved lesson questions, ask AI for the remainder.
    SavedLessonQuestions saved = const SavedLessonQuestions.empty();
    var usedMcq = 0, usedTheory = 0, usedSubjective = 0;
    if (useSavedLessonQuestions) {
      saved = await loadSavedLessonQuestions(
        teacherServerId: teacherServerId,
        schoolServerId: schoolServerId ?? '',
        subject: subject,
        classLevel: classLevel,
        termLabel: termLabel,
        weekNumbers: [for (final t in topics) t.weekNumber],
      );
      usedMcq = min(saved.mcqs.length, totalMcq);
      usedTheory = min(saved.theory.length, totalTheory);
      usedSubjective = min(saved.subjective.length, totalSubjective);
      typeCounts = {
        'MCQ': totalMcq - usedMcq,
        'Theory': totalTheory - usedTheory,
        'Subjective': totalSubjective - usedSubjective,
      };
    }

    final prompt = PromptTemplates.examQuestions(
      subject,
      classLevel,
      topicParts.join('\n'),
      difficulty,
      typeCounts,
      teacherName: teacherName,
      schoolName: schoolName,
    );

    // Tell the AI which saved questions are already in the exam so it does
    // not regenerate them. Only the questions actually reused (taken) are
    // listed; types with nothing reused contribute an empty string.
    final aiPrompt = useSavedLessonQuestions && saved.total > 0
        ? '$prompt\n\n'
            '${PromptTemplates.doNotRepeatInstruction('MCQ', [
                  for (final q in saved.mcqs.take(usedMcq))
                    q['question'].toString(),
                ])}'
            '${PromptTemplates.doNotRepeatInstruction('Theory', [
                  for (final q in saved.theory.take(usedTheory))
                    q['question'].toString(),
                ])}'
            '${PromptTemplates.doNotRepeatInstruction('Subjective', [
                  for (final q in saved.subjective.take(usedSubjective))
                    q['question'].toString(),
                ])}'
        : prompt;

    final remainingTotal =
        typeCounts.values.fold<int>(0, (sum, count) => sum + count);

    // When every requested question is covered by saved lessons, skip the AI
    // call entirely (no credits / daily-limit spend; works offline).
    Map<String, dynamic> content;
    if (useSavedLessonQuestions && remainingTotal == 0) {
      content = {
        'mcqs': const [],
        'theory': const [],
        'subjective': const [],
      };
    } else {
      final result = await aiGenerate(aiPrompt);

      // Parse the AI result into the exam content shape.
      if (result.containsKey('encryptedContent')) {
        content = Map<String, dynamic>.from(result['raw'] as Map);
      } else {
        content = result;
      }
    }
    final examContent = {
      'mcqs': castQuestions(
        content['mcq'] ?? content['mcqs'] ?? content['questions'],
      ),
      'theory': castQuestions(content['theory']),
      'subjective': castQuestions(content['subjective']),
    };

    // Phase 3 hybrid merge: saved questions first, then AI — the requested
    // per-type totals are a contract. The exam must never be written
    // incomplete, so abort (throw) BEFORE the row insert / sync queue.
    if (useSavedLessonQuestions) {
      // The AI may return more than the remainder it was asked for — cap each
      // type to the exact remaining count BEFORE merging so the final exam
      // never exceeds the requested totals (the fill check below only catches
      // shortfall). The pure-AI path keeps whatever the AI returns.
      examContent['mcqs'] =
          castQuestions(examContent['mcqs'])
              .take(typeCounts['MCQ'] ?? 0)
              .toList();
      examContent['theory'] =
          castQuestions(examContent['theory'])
              .take(typeCounts['Theory'] ?? 0)
              .toList();
      examContent['subjective'] =
          castQuestions(examContent['subjective'])
              .take(typeCounts['Subjective'] ?? 0)
              .toList();

      examContent['mcqs'] = [
        ...saved.mcqs.take(totalMcq),
        ...?examContent['mcqs'],
      ];
      examContent['theory'] = [
        ...saved.theory.take(totalTheory),
        ...?examContent['theory'],
      ];
      examContent['subjective'] = [
        ...saved.subjective.take(totalSubjective),
        ...?examContent['subjective'],
      ];
      final missing = <String, int>{};
      void check(String type, int requested, List<dynamic> actual) {
        if (requested > 0 && actual.length < requested) {
          missing[type] = requested - actual.length;
        }
      }

      check('mcqs', totalMcq, examContent['mcqs']!);
      check('theory', totalTheory, examContent['theory']!);
      check('subjective', totalSubjective, examContent['subjective']!);
      if (missing.isNotEmpty) {
        throw ExamIncompleteGenerationException(missing);
      }
    }

    final termLabelStored = _normalizeTermLabelForDraft(termLabel);
    final weekNumber = topics.first.weekNumber;
    final contentJson = jsonEncode(examContent);

    final examId = await db.examsDao.insertExam(
      ExamsCompanion.insert(
        subject: subject,
        classLevel: classLevel,
        topic: topicTitle,
        difficulty: difficulty,
        curriculum: 'NERDC',
        content: contentJson,
        teacherServerId: Value(teacherServerId),
        schoolServerId: schoolServerId != null
            ? Value(schoolServerId)
            : const Value.absent(),
        isUnlocked: const Value(false),
        weekNumber: Value(weekNumber),
        term: Value(termLabelStored),
      ),
    );

    await db.syncQueueDao.insertEntry(
      queueTable: 'exams',
      recordLocalId: examId,
      operation: 'INSERT',
      payload: {
        'subject': subject,
        'class_level': classLevel,
        'topic': topicTitle,
        'difficulty': difficulty,
        'curriculum': 'NERDC',
        'teacher_server_id': teacherServerId,
        'school_server_id': schoolServerId,
        'content': contentJson,
        'is_unlocked': false,
        'week_number': weekNumber,
        'term': termLabelStored,
      },
    );

    return examId;
  }

  /// The exact per-topic type distribution `generateCombinedExam` uses:
  /// MCQ 50% (rounded), Theory 30% (rounded), Subjective = the remainder.
  static (int mcq, int theory, int subjective) distributePerTopicCount(
      int count) {
    final mcq = (count * 0.5).round();
    final theory = (count * 0.3).round();
    return (mcq, theory, count - mcq - theory);
  }

  /// Finds the saved lesson questions for [weekNumbers] of
  /// subject/class/term and returns them validated, in week order.
  /// See plans/phase3_hybrid_exam_checkbox.md §3.2 for the matching rules:
  /// - a lesson matches when `(weekNumber ?? week)` is in [weekNumbers], the
  ///   subject and class match case-insensitively, and the lesson's term is
  ///   empty (legacy rows) or term-normalized-equal to [termLabel];
  /// - multiple lessons for one week → the best wins (most valid questions,
  ///   tie-broken by most recently updated), never merged;
  /// - malformed content / missing `questions` key contributes nothing.
  Future<SavedLessonQuestions> loadSavedLessonQuestions({
    required String teacherServerId,
    required String schoolServerId,
    required String subject,
    required String classLevel,
    required String termLabel,
    required List<int> weekNumbers,
  }) async {
    if (weekNumbers.isEmpty) return const SavedLessonQuestions.empty();
    final lessons = await db.lessonsDao
        .getAllForTeacher(teacherServerId, schoolServerId);
    if (lessons.isEmpty) return const SavedLessonQuestions.empty();

    final weeks = weekNumbers.toSet();
    final termKey = _normalizeTermKey(termLabel);
    final subjectKey = subject.trim().toLowerCase();
    final classKey = classLevel.trim().toLowerCase();

    final byWeek = <int, List<Lesson>>{};
    for (final lesson in lessons) {
      final week = lesson.weekNumber ?? lesson.week;
      if (!weeks.contains(week)) continue;
      if (lesson.subject.trim().toLowerCase() != subjectKey) continue;
      if (lesson.classLevel.trim().toLowerCase() != classKey) continue;
      final lessonTerm = (lesson.term ?? '').trim();
      if (lessonTerm.isNotEmpty &&
          _normalizeTermKey(lessonTerm) != termKey) {
        continue;
      }
      byWeek.putIfAbsent(week, () => []).add(lesson);
    }
    if (byWeek.isEmpty) return const SavedLessonQuestions.empty();

    // Best lesson per week: most valid questions, then most recently updated.
    SavedLessonQuestions bestOf(List<Lesson> candidates) {
      candidates.sort((a, b) {
        final aCount = _decodeLessonQuestions(a).total;
        final bCount = _decodeLessonQuestions(b).total;
        if (aCount != bCount) return bCount.compareTo(aCount);
        return b.updatedAt.compareTo(a.updatedAt);
      });
      return _decodeLessonQuestions(candidates.first);
    }

    final mcqs = <Map<String, dynamic>>[];
    final theory = <Map<String, dynamic>>[];
    final subjective = <Map<String, dynamic>>[];
    for (final week in (byWeek.keys.toList()..sort())) {
      final picked = bestOf(byWeek[week]!);
      mcqs.addAll(picked.mcqs);
      theory.addAll(picked.theory);
      subjective.addAll(picked.subjective);
    }
    return SavedLessonQuestions(
      mcqs: mcqs,
      theory: theory,
      subjective: subjective,
    );
  }

  /// Decodes one lesson's `content['questions']` with the shared validators.
  /// Any malformed JSON / missing key / non-list value contributes nothing.
  SavedLessonQuestions _decodeLessonQuestions(Lesson lesson) {
    List<Map<String, dynamic>> cast(dynamic list) =>
        (list as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map((m) => Map<String, dynamic>.from(m))
            .toList();
    try {
      final content = jsonDecode(lesson.content);
      if (content is! Map<String, dynamic>) {
        return const SavedLessonQuestions.empty();
      }
      final questions = content['questions'];
      if (questions is! Map<String, dynamic>) {
        return const SavedLessonQuestions.empty();
      }
      return SavedLessonQuestions(
        mcqs: validateMcqs(cast(questions['mcqs'])).validQuestions,
        theory:
            validateWrittenQuestions(cast(questions['theory'])).validQuestions,
        subjective:
            validateWrittenQuestions(cast(questions['subjective']))
                .validQuestions,
      );
    } catch (_) {
      return const SavedLessonQuestions.empty();
    }
  }

  /// '1st Term' | 'First' | '1' → '1' (likewise 2/3) — the term matcher,
  /// mirroring the existing `findSchemes` matcher in SchemeOfWorkService.
  String _normalizeTermKey(String term) {
    final t = term.trim().toLowerCase();
    if (t.contains('1st') || t.contains('first') || t == '1') return '1';
    if (t.contains('2nd') || t.contains('second') || t == '2') return '2';
    if (t.contains('3rd') || t.contains('third') || t == '3') return '3';
    return t;
  }

  /// Same per-tier fallback the exam editor uses (`_defaultStorageLimit` in
  /// `exam_editor_screen.dart`) when the remote `lesson_storage_limits` map
  /// has no entry for a tier.
  int _defaultStorageLimit(String tier) {
    switch (tier) {
      case 'free':
        return 10;
      case 'basic':
        return 20;
      case 'standard':
        return 50;
      case 'elite':
        return -1;
      default:
        return 10;
    }
  }

  /// Enforces the school's per-tier exam storage quota using the exact rule
  /// the exam editor applies in `_saveExam` before inserting a new exam:
  /// `limit = lessonStorageLimits[tier] ?? default`, `-1` = unlimited, and the
  /// school's non-deleted exam count must stay within the limit once
  /// [newRowCount] new rows are added. Throws
  /// [ExamStorageLimitExceededException] before anything is created or queued.
  Future<void> _ensureWithinStorageLimit({
    required String? schoolServerId,
    required String subscriptionTier,
    required Map<String, dynamic> lessonStorageLimits,
    required int newRowCount,
  }) async {
    final limit = lessonStorageLimits[subscriptionTier] as int? ??
        _defaultStorageLimit(subscriptionTier);
    if (limit < 0) return; // elite: unlimited
    final currentCount =
        await db.examsDao.countNonDeletedBySchool(schoolServerId ?? '');
    if (currentCount + newRowCount > limit) {
      throw const ExamStorageLimitExceededException();
    }
  }

  /// 'First' / '1st' / '1' → '1st Term' (likewise 2nd/3rd) — the display
  /// label stored on exam rows.
  String _normalizeTermLabelForDraft(String term) {
    final lower = term.trim().toLowerCase();
    if (lower == '1' || lower.startsWith('1st') || lower.contains('first')) {
      return '1st Term';
    }
    if (lower == '2' || lower.startsWith('2nd') || lower.contains('second')) {
      return '2nd Term';
    }
    if (lower == '3' || lower.startsWith('3rd') || lower.contains('third')) {
      return '3rd Term';
    }
    return term.trim();
  }
}
