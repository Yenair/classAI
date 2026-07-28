import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// Provider that fetches all lessons for the current teacher from the database.
final lessonsListProvider = FutureProvider<List<Lesson>>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.watch(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  if (teacherId == null) return [];
  return db.lessonsDao.getAllForTeacher(teacherId);
});

/// Provider that fetches all exams for the current teacher from the database.
final examsListProvider = FutureProvider<List<Exam>>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.watch(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  if (teacherId == null) return [];
  return db.examsDao.getAllForTeacher(teacherId);
});

/// Holds a total count, a draft sub-count, and a secondary count (completed/unlocked).
class CountData {
  final int total;
  final int draftCount;
  final int secondaryCount;
  const CountData({
    required this.total,
    required this.draftCount,
    this.secondaryCount = 0,
  });
}

/// Provider that fetches the most recent lessons for the current teacher.
final recentLessonsProvider = FutureProvider<List<Lesson>>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.watch(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  if (teacherId == null) return [];
  return db.lessonsDao.getRecentLessonsForTeacher(teacherId, limit: 5);
});

/// Provider that fetches the total count of lessons, drafts, and completed
/// for the current teacher.
final lessonCountProvider = FutureProvider<CountData>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.watch(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  if (teacherId == null) {
    return const CountData(total: 0, draftCount: 0, secondaryCount: 0);
  }
  final lessons = await db.lessonsDao.getAllForTeacher(teacherId);
  final draftCount = lessons.where((l) => l.status == 'draft').length;
  final completedCount = lessons.where((l) => l.status == 'completed').length;
  return CountData(
    total: lessons.length,
    draftCount: draftCount,
    secondaryCount: completedCount,
  );
});

/// Provider that fetches the total count of exams, drafts, and unlocked
/// for the current teacher.
final examCountProvider = FutureProvider<CountData>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.watch(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  if (teacherId == null) {
    return const CountData(total: 0, draftCount: 0, secondaryCount: 0);
  }
  final exams = await db.examsDao.getAllForTeacher(teacherId);
  final draftCount = exams.where((e) => !e.isUnlocked).length;
  final unlockedCount = exams.where((e) => e.isUnlocked).length;
  return CountData(
    total: exams.length,
    draftCount: draftCount,
    secondaryCount: unlockedCount,
  );
});

final todayLessonCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.watch(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  if (teacherId == null) return 0;
  final lessons = await db.lessonsDao.getAllForTeacher(teacherId);
  final today = DateTime.now();
  return lessons
      .where((lesson) =>
          lesson.createdAt.year == today.year &&
          lesson.createdAt.month == today.month &&
          lesson.createdAt.day == today.day)
      .length;
});

final lastUpdatedLessonProvider = FutureProvider<Lesson?>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.read(authProvider);
  final teacherId = authData.currentTeacher?.serverId;
  final lessons = await db.lessonsDao.getAll();
  final filtered = teacherId == null
      ? lessons
      : lessons.where((lesson) => lesson.teacherServerId == teacherId).toList();
  if (filtered.isEmpty) return null;
  filtered.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return filtered.first;
});
