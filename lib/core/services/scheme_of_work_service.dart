// lib/core/services/scheme_of_work_service.dart
import 'dart:convert';
import 'package:drift/drift.dart' show Value;
import 'package:classai/core/database/database.dart';

/// Shared persistence for Scheme-of-Work rows and their linked draft
/// lessons/exams. Used by both the admin SchemeOfWorkScreen and the
/// teacher "Plan My Term" auto-generate flow so they never drift apart.
class SchemeOfWorkService {
  final AppDatabase db;
  SchemeOfWorkService(this.db);

  /// Writes one scheme_of_work row per week and auto-creates a linked draft
  /// lesson and exam for each week. Everything runs inside a single database
  /// transaction — a partial failure rolls the whole plan back.
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
                  'term': term,
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

        // Auto-create draft lesson if not already existing
        if (teacherServerId != null && termLabel.isNotEmpty) {
          final existingLessons = await db.lessonsDao.getAll();
          final weekId = weekRecordIds[weekNumber];
          final lessonExists = existingLessons.any((l) {
            if (l.isDeleted || l.status != 'draft') return false;
            // Fallback: same scheme_of_work_id. Lessons created by this
            // service always carry schemeOfWorkId: weekId, so any existing
            // lesson linked to the same scheme record is a duplicate
            // regardless of subject text (which may have been wiped to ''
            // by sync pull).
            if (weekId != null) {
              final existingSchemeId = int.tryParse(l.schemeOfWorkId ?? '');
              if (existingSchemeId == weekId) return true;
            }
            return l.teacherServerId == teacherServerId &&
                l.classLevel == classLevel &&
                (l.term ?? '') == termLabel &&
                (l.weekNumber ?? l.week) == weekNumber;
          });
          if (!lessonExists) {
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
                'classLevel': classLevel,
                'week': weekNumber,
                'topic': topicText,
                'difficulty': 'medium',
                'bloomsVerbs': '',
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
          }

          // Auto-create draft exam if not already existing
          final existingExams = await db.examsDao.getAll();
          final examExists = existingExams.any((e) {
            if (e.isDeleted) return false;
            if (weekId != null) {
              final existingSchemeId = int.tryParse(e.schemeOfWorkId ?? '');
              if (existingSchemeId == weekId) return true;
            }
            return e.teacherServerId == teacherServerId &&
                e.classLevel == classLevel &&
                (e.term ?? '') == termLabel &&
                e.weekNumber == weekNumber;
          });
          if (!examExists) {
            final examContent = jsonEncode({
              'mcqs': [],
              'theory': [],
              'subjective': [],
            });
            final examId = await db.examsDao.insertExam(
              ExamsCompanion.insert(
                subject: subject,
                classLevel: classLevel,
                topic: topicText,
                difficulty: 'medium',
                curriculum: 'NERDC',
                content: examContent,
                teacherServerId: Value(teacherServerId),
                schoolServerId: schoolServerId != null
                    ? Value(schoolServerId)
                    : const Value.absent(),
                isUnlocked: const Value(false),
                schemeOfWorkId: Value(weekId.toString()),
                weekNumber: Value(weekNumber),
                term: Value(termLabel),
              ),
            );
            await db.syncQueueDao.insertEntry(
              queueTable: 'exams',
              recordLocalId: examId,
              operation: 'INSERT',
              payload: {
                'subject': subject,
                'classLevel': classLevel,
                'topic': topicText,
                'difficulty': 'medium',
                'curriculum': 'NERDC',
                'teacher_server_id': teacherServerId,
                'school_server_id': schoolServerId,
                'content': examContent,
                'is_unlocked': false,
                'scheme_of_work_id': weekId.toString(),
                'week_number': weekNumber,
                'term': termLabel,
              },
            );
          }
        }
      }
      return weekRecordIds;
    });
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
            r.classLevel == classLevel &&
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
    final newId = await db.schemeOfWorkDao.insert(
      SchemeOfWorkCompanion.insert(
        schoolId: Value(schoolId),
        teacherId: Value(teacherId),
        subjectId: Value(subjectId),
        term: Value(term),
        classLevel: Value(classLevel),
        weekNumber: Value(weekNumber),
        topic: Value(topic),
        objectives: Value(objectives),
        status: const Value('draft'),
        createdAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
      ),
    );
    if (subjectServerId != null) {
      await db.syncQueueDao.insertEntry(
        queueTable: 'scheme_of_work',
        recordLocalId: newId,
        operation: 'INSERT',
        payload: {
          'teacher_server_id': teacherServerId,
          'school_server_id': schoolServerId,
          'subject_id': subjectServerId,
          'term': term,
          'week_number': weekNumber,
          'topic': topic,
          'objectives': objectives,
          'status': 'draft',
          'admin_edited_topic': null,
          'admin_comment': null,
          'class_level': classLevel,
        },
      );
    }
    return newId;
  }

  /// Deletes an existing plan for the same subject/class/term: scheme rows
  /// are hard-deleted locally (with a sync DELETE queued for server-synced
  /// rows); linked draft lessons/exams are soft-deleted via the existing DAO
  /// methods (isDeleted=true) with a sync DELETE queued when the row has a
  /// server id. Runs inside the caller's transaction.
  Future<void> _deleteExistingPlan({
    required int schoolId,
    required int teacherId,
    required String subject,
    required String classLevel,
    required String term,
  }) async {
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
      final exams = await db.examsDao.getAll();
      for (final exam in exams) {
        if (exam.isDeleted) continue;
        if (exam.schemeOfWorkId != row.id.toString()) continue;
        await db.examsDao.deleteExam(exam.id);
        if (exam.serverId != null && exam.serverId!.isNotEmpty) {
          await db.syncQueueDao.insertEntry(
            queueTable: 'exams',
            recordLocalId: exam.id,
            operation: 'DELETE',
            payload: {'id': exam.id, 'server_id': exam.serverId},
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

/// Parses the AI scheme-of-work response into week maps, mirroring the
/// existing logic in SchemeOfWorkScreen._extractSchemePayload.
/// Shared so the Auto Generate AI fallback and the admin screen agree.
List<Map<String, dynamic>> parseSchemeWeeks(Map<String, dynamic> aiResult) {
  final raw = aiResult['raw'] ?? aiResult;
  Map<String, dynamic> payload;
  if (raw is String) {
    final decoded = jsonDecode(raw);
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
  return (payload['weeks'] as List?)?.cast<Map<String, dynamic>>() ?? [];
}
