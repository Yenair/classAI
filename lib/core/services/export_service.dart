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
      final row = [
        _escapeCsv(lesson.topic),
        lesson.week.toString(),
        _escapeCsv(lesson.topic),
        _escapeCsv(''),
        _escapeCsv(''),
        _escapeCsv(''),
        lesson.createdAt.toIso8601String(),
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
}
