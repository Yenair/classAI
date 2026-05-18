import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../database/database.dart';

/// Service for exporting school data to CSV and JSON formats.
class ExportService {
  final AppDatabase _db;

  ExportService(this._db);

  /// Export lessons for a subject as CSV.
  ///
  /// Uses the spec-defined columns: Title, Week, Topic, Objectives,
  /// Materials, Assessment, Created.
  Future<File> exportLessonsAsCsv(int subjectId) async {
    final lessons = await _db.lessonsDao.getBySubject(subjectId);

    final buffer = StringBuffer();

    // CSV header matching the spec
    buffer.writeln('Title,Week,Topic,Objectives,Materials,Assessment,Created');

    for (final lesson in lessons) {
      // Parse objectives, materials, assessment from content JSON
      String objectives = '';
      String materials = '';
      String assessment = '';
      try {
        final content = jsonDecode(lesson.content) as Map<String, dynamic>;
        objectives = _extractStringField(content, 'objectives');
        materials = _extractStringField(content, 'materials');
        assessment = content['assessment'] as String? ?? '';
      } catch (_) {
        // Content may be encrypted or malformed; leave fields empty
      }

      final row = [
        _escapeCsv(lesson.topic),        // Column 0: Title (no separate title field, use topic)
        lesson.week.toString(),           // Column 1: Week
        _escapeCsv(lesson.topic),         // Column 2: Topic
        _escapeCsv(objectives),           // Column 3: Objectives
        _escapeCsv(materials),            // Column 4: Materials
        _escapeCsv(assessment),           // Column 5: Assessment
        lesson.createdAt.toIso8601String(), // Column 6: Created
      ];
      buffer.writeln(row.join(','));
    }

    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/lessons_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Export all school data as JSON (for inspection/accreditation).
  ///
  /// Uses DAOs for each entity type as specified in the spec.
  Future<File> exportAllAsJson() async {
    final school = await _db.schoolsDao.get();

    final teachers = await _db.teachersDao.getAll();
    final subjects = await _db.subjectsDao.getAll();
    final lessons = await _db.lessonsDao.getAll();
    final exams = await _db.examsDao.getAll();
    final progressLogs = await _db.progressLogsDao.getAll();

    final data = {
      'school': school != null
          ? {
              'school_name': school.schoolName,
              'short_code': school.shortCode,
              'subscription_tier': school.subscriptionTier,
              'active_curriculum': school.activeCurriculum,
              'total_seats': school.totalSeats,
            }
          : null,
      'teachers': teachers
          .map((t) => {
                'name': t.teacherName,
                'email': t.email,
                'role': t.role,
                'is_active': t.isActive,
              })
          .toList(),
      'subjects':
          subjects.map((s) => {'id': s.id, 'name': s.name}).toList(),
      'lessons': lessons
          .map((l) => {
                'topic': l.topic,
                'week': l.week,
                'created_at': l.createdAt.toIso8601String(),
              })
          .toList(),
      'exams': exams
          .map((e) => {
                'topic': e.topic,
                'subject': e.subject,
                'class_level': e.classLevel,
                'difficulty': e.difficulty,
                'created_at': e.createdAt.toIso8601String(),
              })
          .toList(),
      'progress_logs':
          progressLogs.map((p) => {'id': p.id}).toList(),
      'exported_at': DateTime.now().toIso8601String(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final file =
        File('${dir.path}/classai_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// Extract a string from a JSON field that may be a List, String, or null.
  /// If it's a List, join with "; ". If it's a String, use directly.
  String _extractStringField(Map<String, dynamic> content, String key) {
    final value = content[key];
    if (value == null) return '';
    if (value is List) {
      return value.map((e) => e.toString()).join('; ');
    }
    return value.toString();
  }
}
