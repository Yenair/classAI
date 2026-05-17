import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:path_provider/path_provider.dart';
import '../database/database.dart';

/// Service for exporting school data to CSV and JSON formats.
class ExportService {
  final AppDatabase _db;

  ExportService(this._db);

  /// Export all lessons for a subject as CSV.
  ///
  /// Filters by subject name (string) matching the lessons table's subject column.
  Future<File> exportLessonsAsCsv(String subjectName) async {
    final lessons = await (_db.select(_db.lessons)
          ..where((t) => t.subject.equals(subjectName))
          ..orderBy([(t) => OrderingTerm(expression: t.week, mode: OrderingMode.asc)]))
        .get();

    final buffer = StringBuffer();

    // CSV header
    buffer.writeln('Topic,Week,Subject,Class Level,Difficulty,Curriculum,Created');

    for (final lesson in lessons) {
      final row = [
        _escapeCsv(lesson.topic),
        lesson.week.toString(),
        _escapeCsv(lesson.subject),
        _escapeCsv(lesson.classLevel),
        _escapeCsv(lesson.difficulty),
        _escapeCsv(lesson.curriculum),
        lesson.createdAt.toIso8601String(),
      ];
      buffer.writeln(row.join(','));
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/lessons_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Export all lessons for all subjects as CSV.
  Future<File> exportAllLessonsAsCsv() async {
    final lessons = await (_db.select(_db.lessons)
          ..orderBy([(t) => OrderingTerm(expression: t.week, mode: OrderingMode.asc)]))
        .get();

    final buffer = StringBuffer();

    buffer.writeln('Topic,Week,Subject,Class Level,Difficulty,Curriculum,Created');

    for (final lesson in lessons) {
      final row = [
        _escapeCsv(lesson.topic),
        lesson.week.toString(),
        _escapeCsv(lesson.subject),
        _escapeCsv(lesson.classLevel),
        _escapeCsv(lesson.difficulty),
        _escapeCsv(lesson.curriculum),
        lesson.createdAt.toIso8601String(),
      ];
      buffer.writeln(row.join(','));
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/all_lessons_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Export all school data as JSON (for inspection/accreditation).
  Future<File> exportAllAsJson() async {
    School? school;
    try {
      school = await (_db.select(_db.schools)
            ..where((t) => t.isDeleted.equals(false)))
          .getSingle();
    } catch (_) {
      // No school found
    }

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
      'teachers': (await (_db.select(_db.teachers)
              ..where((t) => t.isDeleted.equals(false)))
            .get())
          .map((t) => {
                'name': t.teacherName,
                'email': t.email,
                'role': t.role,
                'is_active': t.isActive,
              })
          .toList(),
      'subjects':
          (await (_db.select(_db.subjects)).get()).map((s) => {'id': s.id}).toList(),
      'lessons': (await (_db.select(_db.lessons)).get())
          .map((l) => {
                'topic': l.topic,
                'subject': l.subject,
                'week': l.week,
                'class_level': l.classLevel,
                'difficulty': l.difficulty,
                'curriculum': l.curriculum,
                'created_at': l.createdAt.toIso8601String(),
              })
          .toList(),
      'exams': (await (_db.select(_db.exams)).get())
          .map((e) => {
                'topic': e.topic,
                'subject': e.subject,
                'class_level': e.classLevel,
                'difficulty': e.difficulty,
                'curriculum': e.curriculum,
                'created_at': e.createdAt.toIso8601String(),
              })
          .toList(),
      'progress_logs':
          (await (_db.select(_db.progressLogs)).get()).map((p) => {'id': p.id}).toList(),
      'exported_at': DateTime.now().toIso8601String(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/classai_export_${DateTime.now().millisecondsSinceEpoch}.json');
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
