// lib/core/services/scheme_of_work_service.dart
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:classai/core/database/database.dart';

/// Shared persistence for Scheme-of-Work rows and their linked draft
/// lessons. Used by both the admin SchemeOfWorkScreen and the teacher
/// "Plan My Term" auto-generate flow so they never drift apart. Exam
/// creation lives in ExamGenerationService — never here.
class SchemeOfWorkService {
  final AppDatabase db;
  SchemeOfWorkService(this.db);

  /// Writes one scheme_of_work row per week and auto-creates a linked draft
  /// lesson for each week. Exams are NEVER created here — exam creation is
  /// exclusively explicit (the exam editor's "Term Exam / CA Test" setup
  /// and single-topic generation flows). Everything runs inside a single
  /// database transaction — a partial failure rolls the whole plan back.
  ///
  /// When [deleteExistingFirst] is true, any existing saved plan for the same
  /// subject/class/term is deleted (scheme rows hard-deleted, linked draft
  /// lessons/exams soft-deleted, DELETE sync entries queued) inside the SAME
  /// transaction, before the new plan is written. This closes the window in
  /// which the old plan is gone but the new one has not saved yet.
  ///
  /// [weeks] is a list of `{'week': int, 'topic': String, 'objectives': String}`
  /// maps, exactly the shape produced by the existing AI parsing and by the
  /// curated NERDC list.
  ///
  /// Returns weekNumber → scheme row id, so callers can keep their week
  /// record lookup in sync (the admin screen needs this for approval).
  Future<Map<int, int>> saveScheme({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String term,
    required List<Map<String, dynamic>> weeks,
    Map<int, int> existingWeekRecordIds = const {},
    bool deleteExistingFirst = false,
  }) {
    return db.transaction(() async {
      if (deleteExistingFirst) {
        await _deleteExistingPlan(
          schoolId: schoolId,
          teacherId: teacherId,
          subject: subject,
          classLevel: classLevel,
          term: term,
        );
      }

      var subjectId = await _resolveOrInsertSubjectId(schoolId, subject);

      final teacher = await db.teachersDao.getById(teacherId);
      final teacherServerId = teacher?.serverId;
      final school = await db.schoolsDao.getByLocalId(schoolId);
      final schoolServerId = school?.serverId;
      final termLabel = _normalizeTermLabelForDraft(term);
      final subjectRow = await db.subjectsDao.getById(subjectId);
      final subjectServerId = subjectRow?.serverId;

      final weekRecordIds = <int, int>{...existingWeekRecordIds};

      for (var index = 0; index < weeks.length; index++) {
        final week = weeks[index];
        final weekNumber = (week['week'] as int?) ?? (index + 1);
        final topicText = week['topic']?.toString().trim() ?? '';
        final objectivesText = week['objectives']?.toString() ?? '';
        final existingId = weekRecordIds[weekNumber];

        int recordId;
        if (existingId != null) {
          // Update existing record (admin re-save path)
          await db.schemeOfWorkDao.updateWeekEntry(
            existingId,
            topic: topicText,
            objectives: objectivesText,
          );
          if (subjectServerId != null) {
            final sowRecord = await db.schemeOfWorkDao.getById(existingId);
            if (sowRecord != null) {
              await db.syncQueueDao.insertEntry(
                queueTable: 'scheme_of_work',
                recordLocalId: existingId,
                operation: 'UPDATE',
                payload: {
                  'teacher_server_id': teacherServerId,
                  'school_server_id': schoolServerId,
                  'subject_id': subjectServerId,
                  'term': normalizeSowTermForServer(term),
                  'week_number': weekNumber,
                  'topic': topicText,
                  'objectives': objectivesText,
                  'status': sowRecord.status,
                  'admin_edited_topic': sowRecord.adminEditedTopic,
                  'admin_comment': sowRecord.adminComment,
                  'class_level': classLevel,
                },
              );
            }
          }
          recordId = existingId;
        } else {
          recordId = await _insertWeekRow(
            schoolId: schoolId,
            teacherId: teacherId,
            subjectId: subjectId,
            subject: subject,
            classLevel: classLevel,
            term: term,
            weekNumber: weekNumber,
            topic: topicText,
            objectives: objectivesText,
            teacherServerId: teacherServerId,
            schoolServerId: schoolServerId,
            subjectServerId: subjectServerId,
          );
        }
        weekRecordIds[weekNumber] = recordId;

        // Auto-create draft lesson if not already existing. When a draft
        // already occupies the week (same teacher/class/term, same subject or
        // wiped-subject), adopt it in place — update topic + re-link — instead
        // of skipping, so a plan always fills every week even when leftover
        // orphan drafts (schemeOfWorkId cleared by the orphaned-link repair)
        // would otherwise block the old skip-guard.
        if (teacherServerId != null && termLabel.isNotEmpty) {
          final existingLessons = await db.lessonsDao.getAll();
          final weekId = weekRecordIds[weekNumber];
          final existingLesson = _findWeekDraftBlocker(
            existingLessons,
            weekId: weekId,
            teacherServerId: teacherServerId,
            classLevel: classLevel,
            termLabel: termLabel,
            weekNumber: weekNumber,
            subject: subject,
          );
          if (existingLesson == null) {
            final lessonContent = jsonEncode({
              'objectives': [],
              'vocabulary': [],
              'materials': [],
              'presentation': [],
              'assessment': '',
              'homework': '',
            });
            final lessonId = await db.lessonsDao.insertLesson(
              LessonsCompanion.insert(
                subject: subject,
                classLevel: classLevel,
                week: weekNumber,
                topic: topicText,
                difficulty: 'medium',
                bloomsVerbs: '',
                curriculum: 'NERDC',
                content: lessonContent,
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                schemeOfWorkId: Value(weekId.toString()),
                weekNumber: Value(weekNumber),
                isUnlocked: const Value(false),
                status: const Value('draft'),
                term: Value(termLabel),
              ),
            );
            await db.syncQueueDao.insertEntry(
              queueTable: 'lessons',
              recordLocalId: lessonId,
              operation: 'INSERT',
              payload: {
                'subject': subject,
                'class_level': classLevel,
                'week': weekNumber,
                'topic': topicText,
                'difficulty': 'medium',
                'blooms_verbs': '',
                'curriculum': 'NERDC',
                'teacher_server_id': teacherServerId,
                'school_server_id': schoolServerId,
                'content': lessonContent,
                'content_hash': lessonContent.hashCode.toString(),
                'is_unlocked': false,
                'scheme_of_work_id': weekId.toString(),
                'week_number': weekNumber,
                'term': termLabel,
              },
            );
          } else {
            await _updateDraftLessonInPlace(
              lesson: existingLesson,
              weekId: weekId,
              subject: subject,
              classLevel: classLevel,
              weekNumber: weekNumber,
              topic: topicText,
              termLabel: termLabel,
              teacherServerId: teacherServerId,
              schoolServerId: schoolServerId,
            );
          }
        }
      }
      return weekRecordIds;
    });
  }

  /// Finds the non-deleted draft that occupies [weekNumber] for the same
  /// teacher/class/term — the row the old duplicate-guard would skip. Returns
  /// null when the week is free (fresh insert).
  ///
  /// A lesson linked to the same scheme record always counts regardless of
  /// subject text (which may have been wiped to '' by sync pull). Otherwise
  /// the teacher/class/term/week slot must also share the subject name
  /// (case-insensitive, or empty) so a different subject's draft is never
  /// adopted or clobbered.
  Lesson? _findWeekDraftBlocker(
    List<Lesson> lessons, {
    required int? weekId,
    required String teacherServerId,
    required String classLevel,
    required String termLabel,
    required int weekNumber,
    required String subject,
  }) {
    for (final lesson in lessons) {
      if (lesson.isDeleted ||
          (lesson.status != 'draft' && lesson.status != 'generated')) {
        continue;
      }
      if (weekId != null) {
        final existingSchemeId = int.tryParse(lesson.schemeOfWorkId ?? '');
        if (existingSchemeId == weekId) return lesson;
      }
      if (lesson.teacherServerId == teacherServerId &&
          lesson.classLevel == classLevel &&
          (lesson.term ?? '') == termLabel &&
          (lesson.weekNumber ?? lesson.week) == weekNumber &&
          _matchesSubject(lesson.subject, subject)) {
        return lesson;
      }
    }
    return null;
  }

  /// True when the stored lesson subject matches the plan's subject
  /// (case-insensitive), or is empty — sync-pull can wipe subject to '' on
  /// rows pushed before the subject→subject_id resolution, and such rows
  /// still occupy the teacher/class/term/week slot.
  bool _matchesSubject(String? storedSubject, String subject) {
    final a = (storedSubject ?? '').trim().toLowerCase();
    final b = subject.trim().toLowerCase();
    return a.isEmpty || a == b;
  }

  /// Re-adopts an existing draft lesson into the newly generated plan:
  /// updates topic/link in place and queues the sync write instead of
  /// skipping the week. Content the teacher already wrote is preserved.
  Future<void> _updateDraftLessonInPlace({
    required Lesson lesson,
    required int? weekId,
    required String subject,
    required String classLevel,
    required int weekNumber,
    required String topic,
    required String termLabel,
    required String teacherServerId,
    required String? schoolServerId,
  }) async {
    final schemeOfWorkId = weekId?.toString();
    await db.lessonsDao.updateLesson(
      lesson.id,
      LessonsCompanion(
        subject: Value(subject),
        classLevel: Value(classLevel),
        week: Value(weekNumber),
        topic: Value(topic),
        schemeOfWorkId: schemeOfWorkId != null
            ? Value(schemeOfWorkId)
            : const Value(null),
        weekNumber: Value(weekNumber),
        term: Value(termLabel),
        status: const Value('draft'),
        updatedAt: Value(DateTime.now()),
      ),
    );

    final payload = <String, dynamic>{
      'subject': subject,
      'class_level': classLevel,
      'week': weekNumber,
      'topic': topic,
      'difficulty': lesson.difficulty,
      'blooms_verbs': lesson.bloomsVerbs,
      'curriculum': lesson.curriculum,
      'teacher_server_id': teacherServerId,
      'school_server_id': schoolServerId,
      'content': lesson.content,
      'is_unlocked': lesson.isUnlocked,
      'status': 'draft',
      if (schemeOfWorkId != null) 'scheme_of_work_id': schemeOfWorkId,
      'week_number': weekNumber,
      'term': termLabel,
    };

    final hasServerId = lesson.serverId != null && lesson.serverId!.isNotEmpty;
    if (hasServerId) {
      // Row already exists on the server — push an UPDATE. sync_service
      // injects server_id into UPDATE payloads that omit it.
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: lesson.id,
        operation: 'UPDATE',
        payload: payload,
      );
    } else {
      // Never synced — a fresh INSERT creates the server row (sync_service's
      // stale-INSERT recovery converts any duplicate to an upsert).
      await db.syncQueueDao.insertEntry(
        queueTable: 'lessons',
        recordLocalId: lesson.id,
        operation: 'INSERT',
        payload: {
          ...payload,
          'content_hash': lesson.contentHash ??
              lesson.content.hashCode.toString(),
        },
      );
    }
  }

  /// Finds an existing saved plan for the same subject/class/term.
  /// Used by the Auto Generate flow to warn before recreating.
  Future<List<SchemeOfWorkData>> findSchemes({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String term,
  }) async {
    final subjectId = await findSubjectId(schoolId: schoolId, subject: subject);
    if (subjectId == null) return const [];
    final rows = await db.schemeOfWorkDao.getBySchool(schoolId);
    final termKey = _normalizeTermKey(term);
    return rows
        .where((r) =>
            !r.isDeleted &&
            r.teacherId == teacherId &&
            r.subjectId == subjectId &&
            _normalizeClassKey(r.classLevel) == _normalizeClassKey(classLevel) &&
            _normalizeTermKey(r.term) == termKey)
        .toList();
  }

  /// Looks up a subject id WITHOUT creating the subject row.
  Future<int?> findSubjectId({
    required int schoolId,
    required String subject,
  }) async {
    final school = await db.schoolsDao.getByLocalId(schoolId);
    final schoolServerId = school?.serverId;
    final row = schoolServerId != null
        ? await db.subjectsDao.getByNameAndSchool(subject, schoolServerId)
        : await db.subjectsDao.getByName(subject);
    return row?.id;
  }

  Future<int> _resolveOrInsertSubjectId(int schoolId, String subject) async {
    final existing = await findSubjectId(schoolId: schoolId, subject: subject);
    if (existing != null) return existing;
    final school = await db.schoolsDao.getByLocalId(schoolId);
    final schoolServerId = school?.serverId;
    final subjectId = await db.subjectsDao.insert(
      name: subject,
      schoolId: schoolServerId,
    );
    await db.syncQueueDao.insertEntry(
      queueTable: 'subjects',
      recordLocalId: subjectId,
      operation: 'INSERT',
      payload: {'name': subject, 'school_id': schoolServerId},
    );
    return subjectId;
  }

  Future<int> _insertWeekRow({
    required int schoolId,
    required int teacherId,
    required int subjectId,
    required String subject,
    required String classLevel,
    required String term,
    required int weekNumber,
    required String topic,
    required String objectives,
    required String? teacherServerId,
    required String? schoolServerId,
    required String? subjectServerId,
  }) async {
    // ── Natural-key guard ──────────────────────────────────────────
    // If an unsynced local row already occupies the same natural-key
    // slot, adopt it instead of inserting a duplicate.
    final existing = await db.schemeOfWorkDao.getByNaturalKey(
      schoolId: schoolId,
      teacherId: teacherId,
      subjectId: subjectId,
      term: normalizeSowTermForServer(term),
      weekNumber: weekNumber,
    );
    if (existing != null &&
        (existing.serverId == null || existing.serverId!.isEmpty)) {
      // Update the existing row with fresh content.
      await db.schemeOfWorkDao.updateWeekEntry(
        existing.id,
        topic: topic,
        objectives: objectives,
      );
      debugPrint(
        '[sow] _insertWeekRow: adopted existing unsynced row '
        '${existing.id} (natural key match, week $weekNumber)',
      );
      // Still queue a sync INSERT so the row reaches the server.
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: existing.id,
        operation: 'INSERT',
        payload: {
          'teacher_server_id': teacherServerId,
          'school_server_id': schoolServerId,
          'subject_id': subjectServerId,
          'subject_name': subject,
          'term': normalizeSowTermForServer(term),
          'week_number': weekNumber,
          'topic': topic,
          'objectives': objectives,
          'status': 'draft',
          'admin_edited_topic': null,
          'admin_comment': null,
          'class_level': classLevel,
        },
      );
      return existing.id;
    }
    // No unsynced match — proceed with INSERT.
    final newId = await db.schemeOfWorkDao.insert(
      SchemeOfWorkCompanion.insert(
        schoolId: Value(schoolId),
        teacherId: Value(teacherId),
        subjectId: Value(subjectId),
        term: Value(normalizeSowTermForServer(term)),
        classLevel: Value(classLevel),
        weekNumber: Value(weekNumber),
        topic: Value(topic),
        objectives: Value(objectives),
        status: const Value('draft'),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    // Always queue the INSERT sync entry, even when the subject is brand-new
    // (subjectServerId == null) and has no server UUID yet. sync-push resolves
    // the subject by name via subject_name when subject_id is not a valid UUID.
    await db.syncQueueDao.insertEntry(
      queueTable: 'scheme_of_work',
      recordLocalId: newId,
      operation: 'INSERT',
      payload: {
        'teacher_server_id': teacherServerId,
        'school_server_id': schoolServerId,
        'subject_id': subjectServerId,
        'subject_name': subject,
        'term': normalizeSowTermForServer(term),
        'week_number': weekNumber,
        'topic': topic,
        'objectives': objectives,
        'status': 'draft',
        'admin_edited_topic': null,
        'admin_comment': null,
        'class_level': classLevel,
      },
    );
    return newId;
  }

  /// Deletes an existing plan for the same subject/class/term: scheme rows
  /// are hard-deleted locally (with a sync DELETE queued for server-synced
  /// rows); linked draft lessons are soft-deleted via the existing DAO
  /// methods (isDeleted=true) with a sync DELETE queued when the row has a
  /// server id. Exams are NEVER created or deleted here — they are no longer
  /// tied to the plan lifecycle. Runs inside the caller's transaction.
  ///
  /// Also soft-deletes ORPHAN draft lessons for the same teacher, subject,
  /// class and term whose `schemeOfWorkId` is null/empty. Those rows are not
  /// linked to any scheme row (e.g. leftovers of a crashed partial generation
  /// whose links were cleared by the orphaned-link repair) so the scheme-
  /// linked loop above leaves them behind — and they would otherwise match
  /// the duplicate-guard in saveScheme and block the fresh plan from filling
  /// every week.
  Future<void> _deleteExistingPlan({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String term,
  }) async {
    final teacher = await db.teachersDao.getById(teacherId);
    final teacherServerId = teacher?.serverId;

    final rows = await findSchemes(
      schoolId: schoolId,
      teacherId: teacherId,
      subject: subject,
      classLevel: classLevel,
      term: term,
    );
    for (final row in rows) {
      final lessons = await db.lessonsDao.getAll();
      for (final lesson in lessons) {
        if (lesson.isDeleted) continue;
        if (lesson.schemeOfWorkId != row.id.toString()) continue;
        await db.lessonsDao.deleteLesson(lesson.id);
        if (lesson.serverId != null && lesson.serverId!.isNotEmpty) {
          await db.syncQueueDao.insertEntry(
            queueTable: 'lessons',
            recordLocalId: lesson.id,
            operation: 'DELETE',
            payload: {'id': lesson.id, 'server_id': lesson.serverId},
          );
        }
      }
      if (row.serverId != null && row.serverId!.isNotEmpty) {
        await db.syncQueueDao.insertEntry(
          queueTable: 'scheme_of_work',
          recordLocalId: row.id,
          operation: 'DELETE',
          payload: {'id': row.id, 'server_id': row.serverId},
        );
      }
      await db.schemeOfWorkDao.hardDelete(row.id);
    }

    // ── Orphan draft cleanup ─────────────────────────────────────────────
    // Draft lessons for this teacher/class/term that are NOT linked to any
    // scheme row (schemeOfWorkId null/empty) survive the scheme-linked
    // deletion above. They would otherwise match the duplicate-guard in
    // saveScheme (same teacher/class/term/week) and block the fresh plan, so
    // a replace would only ever fill the weeks that had no leftover draft.
    // Treat them as part of the plan being replaced. Subject matching is
    // case-insensitive and also matches an empty stored subject (sync-pull
    // can wipe it to ''); a draft of a DIFFERENT subject is left alone.
    if (teacherServerId != null) {
      final termLabel = _normalizeTermLabelForDraft(term);
      final normalizedClass = _normalizeClassKey(classLevel);

      final orphanLessons = await db.lessonsDao.getAll();
      for (final lesson in orphanLessons) {
        // Generated lessons count as plan content too — they are deleted on a
        // deliberate plan replace (the same way scheme-linked lessons of any
        // status are), so a fresh plan is not blocked by leftover rows.
        if (lesson.isDeleted ||
            (lesson.status != 'draft' && lesson.status != 'generated')) {
          continue;
        }
        if (lesson.schemeOfWorkId != null && lesson.schemeOfWorkId!.isNotEmpty) {
          continue; // linked to a scheme row — handled above
        }
        if (lesson.teacherServerId != teacherServerId) continue;
        if (_normalizeClassKey(lesson.classLevel) != normalizedClass) continue;
        if (_normalizeTermLabelForDraft(lesson.term ?? '') != termLabel) {
          continue;
        }
        if (!_matchesSubject(lesson.subject, subject)) continue;
        await db.lessonsDao.deleteLesson(lesson.id);
        if (lesson.serverId != null && lesson.serverId!.isNotEmpty) {
          await db.syncQueueDao.insertEntry(
            queueTable: 'lessons',
            recordLocalId: lesson.id,
            operation: 'DELETE',
            payload: {'id': lesson.id, 'server_id': lesson.serverId},
          );
        }
      }
    }
  }

  /// 'JSS3' / 'JSS 3' / 'jss3' → 'jss 3' (likewise SSS) so plan lookups are
  /// stable regardless of how a class label was stored (legacy/synced data
  /// often has no space).
  String _normalizeClassKey(String value) {
    final compact = value.trim().toLowerCase().replaceAll(' ', '');
    final match = RegExp(r'^(jss|sss)(\d)$').firstMatch(compact);
    if (match != null) return '${match.group(1)} ${match.group(2)}';
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _normalizeTermLabelForDraft(String term) {
    final lower = term.trim().toLowerCase();
    if (lower == '1' || lower.startsWith('1st') || lower.contains('first')) return '1st Term';
    if (lower == '2' || lower.startsWith('2nd') || lower.contains('second')) return '2nd Term';
    if (lower == '3' || lower.startsWith('3rd') || lower.contains('third')) return '3rd Term';
    return term.trim();
  }

  String _normalizeTermKey(String term) {
    final lower = term.trim().toLowerCase();
    if (lower == '1' || lower.startsWith('1st') || lower.contains('first')) return '1st';
    if (lower == '2' || lower.startsWith('2nd') || lower.contains('second')) return '2nd';
    if (lower == '3' || lower.startsWith('3rd') || lower.contains('third')) return '3rd';
    return lower;
  }
}

/// Normalises a scheme-of-work term to the lowercase value the server CHECK
/// constraint (`scheme_of_work_term_check`) accepts: 'first' / 'second' /
/// 'third'. The client historically queued title-case terms ('First'), which
/// the constraint rejects, so every scheme_of_work sync payload normalises
/// through here before it is queued.
String normalizeSowTermForServer(String term) {
  switch (term.trim().toLowerCase()) {
    case 'first':
    case '1st':
    case '1st term':
      return 'first';
    case 'second':
    case '2nd':
    case '2nd term':
      return 'second';
    case 'third':
    case '3rd':
    case '3rd term':
      return 'third';
    default:
      return term.trim().toLowerCase();
  }
}

/// Extracts the first JSON object/array embedded in [text], tolerating the
/// markdown code fences and introductory prose the model sometimes adds
/// despite the prompt (e.g. "```json\n{...}\n```" or "Here is the plan: {...}").
/// Returns null when nothing parseable is found.
dynamic _extractJsonFromText(String text) {
  final trimmed = text.trim();
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(trimmed);
  final candidate = fence != null ? fence.group(1)!.trim() : trimmed;

  final firstBrace = candidate.indexOf('{');
  final lastBrace = candidate.lastIndexOf('}');
  if (firstBrace != -1 && lastBrace > firstBrace) {
    try {
      return jsonDecode(candidate.substring(firstBrace, lastBrace + 1));
    } catch (_) {
      // Not a JSON object — try an array below.
    }
  }
  final firstBracket = candidate.indexOf('[');
  final lastBracket = candidate.lastIndexOf(']');
  if (firstBracket != -1 && lastBracket > firstBracket) {
    try {
      return jsonDecode(candidate.substring(firstBracket, lastBracket + 1));
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Parses the AI scheme-of-work response into week maps, mirroring the
/// existing logic in SchemeOfWorkScreen._extractSchemePayload.
/// Shared so the Auto Generate AI fallback and the admin screen agree.
List<Map<String, dynamic>> parseSchemeWeeks(Map<String, dynamic> aiResult) {
  final raw = aiResult['raw'] ?? aiResult;
  Map<String, dynamic> payload;
  if (raw is String) {
    final decoded = _extractJsonFromText(raw) ?? raw;
    if (decoded is Map<String, dynamic>) {
      payload = decoded;
    } else if (decoded is Map) {
      payload = decoded.cast<String, dynamic>();
    } else {
      throw FormatException('Scheme response did not contain a JSON object');
    }
  } else if (raw is Map<String, dynamic>) {
    payload = raw;
  } else if (raw is Map) {
    payload = raw.cast<String, dynamic>();
  } else {
    throw FormatException('Scheme response did not contain a JSON object');
  }

  // The AI proxies wrap model output that is not strict JSON as
  // { "text": "<raw output>" }. The weeks array may still be recoverable
  // from that embedded text (typically fenced or prose-wrapped JSON).
  if (payload['weeks'] == null && payload['text'] is String) {
    final decoded = _extractJsonFromText(payload['text'] as String);
    if (decoded is Map<String, dynamic>) {
      payload = decoded;
    } else if (decoded is Map) {
      payload = decoded.cast<String, dynamic>();
    }
  }

  // Surface provider/model error objects instead of a silent empty list.
  final error = payload['error'];
  if (error != null) {
    throw FormatException(
      'Scheme response contained an error: '
      '${error is String ? error : jsonEncode(error)}',
    );
  }

  // Some models nest the weeks array under a wrapper key.
  if (payload['weeks'] == null) {
    for (final key in const ['scheme_of_work', 'data', 'result', 'content']) {
      final nested = payload[key];
      if (nested is Map<String, dynamic> && nested['weeks'] != null) {
        payload = nested;
        break;
      } else if (nested is Map) {
        final cast = nested.cast<String, dynamic>();
        if (cast['weeks'] != null) {
          payload = cast;
          break;
        }
      }
    }
  }

  final weeksValue = payload['weeks'];
  if (weeksValue is String) {
    // The model returned the weeks array as a JSON string.
    try {
      final decoded = jsonDecode(weeksValue);
      if (decoded is List) {
        return decoded.cast<Map<String, dynamic>>().toList();
      }
    } catch (_) {
      // Fall through to the empty result below.
    }
    return const [];
  }
  if (weeksValue == null) return const [];
  if (weeksValue is List) {
    return weeksValue.cast<Map<String, dynamic>>().toList();
  }
  throw FormatException(
    'Scheme response "weeks" was not a list: ${weeksValue.runtimeType}',
  );
}
