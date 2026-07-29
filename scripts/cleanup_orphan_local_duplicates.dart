// ============================================================================
// Local-side (Drift) cleanup: Remove orphan server_id=NULL duplicate lessons
// and exams from the local SQLite database.
//
// HOW TO USE:
//   import this file and call:
//     await printDiagnosticSummary(db);     // dry-run: prints what would be deleted
//     await runFullCleanup(db);             // actually deletes orphans
//
// WHAT THIS DOES:
//   For each group of serverId IS NULL rows sharing the same curriculum slot
//   identity, keeps the row with the LATEST createdAt and removes the earlier
//   orphan(s). Also cleans up:
//     - sync_queue entries referencing the removed local IDs
//     - version_hashes entries referencing the removed local IDs
//
// CURRICULUM-SLOT IDENTITY:
//   - Lessons: (schoolServerId, subject, classLevel, week, topic, teacherServerId)
//   - Exams:   (schoolServerId, subject, classLevel, topic, teacherServerId)
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../lib/core/database/database.dart';

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  BACKUP — Write orphan rows to a timestamped JSONL file on disk        ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// Writes a backup JSONL file at [documentsDir]/cleanup_backup_{tag}_{timestamp}.jsonl
/// and returns the absolute file path.
///
/// Each line is `jsonEncode(orphan.toJson())` — one JSON object per orphan row.
/// The file path is also printed so it can be pulled from the device via adb.
Future<String> _writeBackupFile({
  required String tag,
  required List<Map<String, dynamic>> orphanRows,
}) async {
  if (orphanRows.isEmpty) return '';

  final dir = await getApplicationDocumentsDirectory();
  final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
  final filePath = p.join(dir.path, 'cleanup_backup_${tag}_$timestamp.jsonl');

  final lines = orphanRows.map(jsonEncode).join('\n');
  await File(filePath).writeAsString('$lines\n');

  print('📦 BACKUP file saved to: $filePath');
  print('   (${orphanRows.length} orphan rows backed up)');
  return filePath;
}

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  DIAGNOSTIC — Count orphan pairs before cleanup                        ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// Prints a full diagnostic report of all orphan duplicate groups found
/// in the local lessons and exams tables.
Future<void> printDiagnosticSummary(AppDatabase db) async {
  print('═══ ORPHAN DUPLICATE DIAGNOSTIC ═══');

  // ── Lessons ─────────────────────────────────────────────────────
  final allLessons = await (db.select(db.lessons)
        ..where((t) => t.serverId.isNull())
        ..where((t) => t.isDeleted.equals(false)))
      .get();

  final lessonGroups = <String, List<Lesson>>{};
  for (final lesson in allLessons) {
    final key =
        '${lesson.schoolServerId ?? ''}|${lesson.subject}|${lesson.classLevel}|${lesson.week}|${lesson.topic}|${lesson.teacherServerId ?? ''}';
    (lessonGroups[key] ??= []).add(lesson);
  }

  final duplicateLessonGroups = <List<Lesson>>[];
  int lessonsToDelete = 0;
  int lessonsToKeep = 0;

  for (final list in lessonGroups.values) {
    if (list.length <= 1) continue;
    final sorted = List<Lesson>.from(list)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final keeper = sorted.first;
    final orphans = sorted.skip(1).toList();
    duplicateLessonGroups.add(sorted);
    lessonsToDelete += orphans.length;
    lessonsToKeep += 1;

    print('\n📘 Lesson duplicate group:');
    print('   Slot: schoolServerId=${keeper.schoolServerId}, '
        'subject=${keeper.subject}, classLevel=${keeper.classLevel}, '
        'week=${keeper.week}, topic=${keeper.topic}, '
        'teacherServerId=${keeper.teacherServerId}');
    print('   👑 KEEPER:  id=${keeper.id}, createdAt=${keeper.createdAt}'
        '${keeper.serverId != null ? ", serverId=${keeper.serverId}" : ""}');
    for (final orphan in orphans) {
      print('   🗑️  ORPHAN: id=${orphan.id}, createdAt=${orphan.createdAt}'
          '${orphan.serverId != null ? ", serverId=${orphan.serverId}" : ""}');
    }
  }

  // ── Exams ───────────────────────────────────────────────────────
  final allExams = await (db.select(db.exams)
        ..where((t) => t.serverId.isNull())
        ..where((t) => t.isDeleted.equals(false)))
      .get();

  final examGroups = <String, List<Exam>>{};
  for (final exam in allExams) {
    final key =
        '${exam.schoolServerId ?? ''}|${exam.subject}|${exam.classLevel}|${exam.topic}|${exam.teacherServerId ?? ''}';
    (examGroups[key] ??= []).add(exam);
  }

  int examsToDelete = 0;
  int examsToKeep = 0;

  for (final list in examGroups.values) {
    if (list.length <= 1) continue;
    final sorted = List<Exam>.from(list)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final keeper = sorted.first;
    final orphans = sorted.skip(1).toList();
    examsToDelete += orphans.length;
    examsToKeep += 1;

    print('\n📗 Exam duplicate group:');
    print('   Slot: schoolServerId=${keeper.schoolServerId}, '
        'subject=${keeper.subject}, classLevel=${keeper.classLevel}, '
        'topic=${keeper.topic}, teacherServerId=${keeper.teacherServerId}');
    print('   👑 KEEPER:  id=${keeper.id}, createdAt=${keeper.createdAt}');
    for (final orphan in orphans) {
      print('   🗑️  ORPHAN: id=${orphan.id}, createdAt=${orphan.createdAt}');
    }
  }

  // ── Summary ─────────────────────────────────────────────────────
  print('\n═══ SUMMARY ═══');
  print('Duplicate lesson groups: ${duplicateLessonGroups.length}');
  print('  → Lessons to DELETE: $lessonsToDelete');
  print('  → Lessons to KEEP:   $lessonsToKeep');
  print('Duplicate exam groups: ${examGroups.values.where((l) => l.length > 1).length}');
  print('  → Exams to DELETE:   $examsToDelete');
  print('  → Exams to KEEP:     $examsToKeep');

  // ── Sync queue status for orphan lesson rows ────────────────────
  final allOrphanLessonIds = <int>{};
  for (final list in lessonGroups.values) {
    if (list.length <= 1) continue;
    final sorted = List<Lesson>.from(list)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final orphan in sorted.skip(1)) {
      allOrphanLessonIds.add(orphan.id);
    }
  }

  if (allOrphanLessonIds.isNotEmpty) {
    for (final id in allOrphanLessonIds) {
      final queueEntries = await (db.select(db.syncQueue)
            ..where((t) => t.queueTable.equals('lessons'))
            ..where((t) => t.recordLocalId.equals(id)))
          .get();
      if (queueEntries.isNotEmpty) {
        print('\n📋 Sync queue entries for orphan lesson id=$id:');
        for (final q in queueEntries) {
          print('   queueId=${q.id}, op=${q.operation}, '
              'attempts=${q.attempts}, isTerminal=${q.isTerminal}');
        }
      }
    }
  }

  // ── Sync queue status for orphan exam rows ─────────────────────
  final allOrphanExamIds = <int>{};
  for (final list in examGroups.values) {
    if (list.length <= 1) continue;
    final sorted = List<Exam>.from(list)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final orphan in sorted.skip(1)) {
      allOrphanExamIds.add(orphan.id);
    }
  }

  if (allOrphanExamIds.isNotEmpty) {
    for (final id in allOrphanExamIds) {
      final queueEntries = await (db.select(db.syncQueue)
            ..where((t) => t.queueTable.equals('exams'))
            ..where((t) => t.recordLocalId.equals(id)))
          .get();
      if (queueEntries.isNotEmpty) {
        print('\n📋 Sync queue entries for orphan exam id=$id:');
        for (final q in queueEntries) {
          print('   queueId=${q.id}, op=${q.operation}, '
              'attempts=${q.attempts}, isTerminal=${q.isTerminal}');
        }
      }
    }
  }

  print('\n═══ END DIAGNOSTIC ═══');
}

// ╔══════════════════════════════════════════════════════════════════════════╗
// ║  CLEANUP FUNCTIONS                                                     ║
// ╚══════════════════════════════════════════════════════════════════════════╝

/// Deletes orphan duplicate lessons (serverId IS NULL, sharing the same
/// curriculum slot, keeping only the latest createdAt).
/// Also cleans up sync_queue and version_hashes references.
///
/// SAFETY: All three deletes (sync_queue, version_hashes, lessons) run inside
/// a single atomic Drift transaction — if any step fails, none are committed.
/// Before deletion, a timestamped JSONL backup file is written to the device's
/// documents directory with the full row data of every orphan about to be
/// deleted.
Future<void> cleanupOrphanDuplicateLessons(AppDatabase db) async {
  // 1. Find all lessons with serverId IS NULL
  final allOrphans = await (db.select(db.lessons)
        ..where((t) => t.serverId.isNull())
        ..where((t) => t.isDeleted.equals(false)))
      .get();

  // 2. Group by curriculum-slot identity
  final groups = <String, List<Lesson>>{};
  for (final lesson in allOrphans) {
    final key =
        '${lesson.schoolServerId ?? ''}|${lesson.subject}|${lesson.classLevel}|${lesson.week}|${lesson.topic}|${lesson.teacherServerId ?? ''}';
    (groups[key] ??= []).add(lesson);
  }

  // 3. For each group with >1 member, keep the latest, delete the rest
  final idsToDelete = <int>{};
  final backupRows = <Map<String, dynamic>>[];
  for (final list in groups.values) {
    if (list.length <= 1) continue;
    final sorted = List<Lesson>.from(list)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final orphan in sorted.skip(1)) {
      idsToDelete.add(orphan.id);
      backupRows.add(orphan.toJson());
    }
  }

  if (idsToDelete.isEmpty) {
    print('✅ No orphan duplicate lessons to clean up.');
    return;
  }

  // ── Backup: write orphan rows to a timestamped JSONL file on disk ──
  await _writeBackupFile(tag: 'lessons', orphanRows: backupRows);

  print('🗑️  Cleaning up ${idsToDelete.length} orphan duplicate lessons...');

  // ── Atomic transaction: all three deletes succeed or none do ──
  await db.transaction(() async {
    // 4. Delete sync_queue entries referencing these IDs
    await (db.delete(db.syncQueue)
          ..where((t) => t.queueTable.equals('lessons'))
          ..where((t) => t.recordLocalId.isIn(idsToDelete)))
        .go();

    // 5. Delete version_hashes entries referencing these IDs
    await (db.delete(db.versionHashes)
          ..where((t) => t.table.equals('lessons'))
          ..where((t) => t.recordLocalId.isIn(idsToDelete)))
        .go();

    // 6. Delete the orphan lessons themselves
    await (db.delete(db.lessons)
          ..where((t) => t.id.isIn(idsToDelete)))
        .go();
  });

  print('✅ Done — deleted ${idsToDelete.length} orphan duplicate lessons');
}

/// Deletes orphan duplicate exams (serverId IS NULL, sharing the same
/// curriculum slot, keeping only the latest createdAt).
/// Also cleans up sync_queue and version_hashes references.
///
/// SAFETY: All three deletes (sync_queue, version_hashes, exams) run inside
/// a single atomic Drift transaction — if any step fails, none are committed.
/// Before deletion, a timestamped JSONL backup file is written to the device's
/// documents directory with the full row data of every orphan about to be
/// deleted.
Future<void> cleanupOrphanDuplicateExams(AppDatabase db) async {
  // 1. Find all exams with serverId IS NULL
  final allOrphans = await (db.select(db.exams)
        ..where((t) => t.serverId.isNull())
        ..where((t) => t.isDeleted.equals(false)))
      .get();

  // 2. Group by curriculum-slot identity
  final groups = <String, List<Exam>>{};
  for (final exam in allOrphans) {
    final key =
        '${exam.schoolServerId ?? ''}|${exam.subject}|${exam.classLevel}|${exam.topic}|${exam.teacherServerId ?? ''}';
    (groups[key] ??= []).add(exam);
  }

  // 3. For each group with >1 member, keep the latest, delete the rest
  final idsToDelete = <int>{};
  final backupRows = <Map<String, dynamic>>[];
  for (final list in groups.values) {
    if (list.length <= 1) continue;
    final sorted = List<Exam>.from(list)
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    for (final orphan in sorted.skip(1)) {
      idsToDelete.add(orphan.id);
      backupRows.add(orphan.toJson());
    }
  }

  if (idsToDelete.isEmpty) {
    print('✅ No orphan duplicate exams to clean up.');
    return;
  }

  // ── Backup: write orphan rows to a timestamped JSONL file on disk ──
  await _writeBackupFile(tag: 'exams', orphanRows: backupRows);

  print('🗑️  Cleaning up ${idsToDelete.length} orphan duplicate exams...');

  // ── Atomic transaction: all three deletes succeed or none do ──
  await db.transaction(() async {
    // 4. Delete sync_queue entries referencing these IDs
    await (db.delete(db.syncQueue)
          ..where((t) => t.queueTable.equals('exams'))
          ..where((t) => t.recordLocalId.isIn(idsToDelete)))
        .go();

    // 5. Delete version_hashes entries referencing these IDs
    await (db.delete(db.versionHashes)
          ..where((t) => t.table.equals('exams'))
          ..where((t) => t.recordLocalId.isIn(idsToDelete)))
        .go();

    // 6. Delete the orphan exams themselves
    await (db.delete(db.exams)
          ..where((t) => t.id.isIn(idsToDelete)))
        .go();
  });

  print('✅ Done — deleted ${idsToDelete.length} orphan duplicate exams');
}

/// Runs diagnostics AND then cleanup for both lessons and exams.
Future<void> runFullCleanup(AppDatabase db) async {
  print('═══ STEP 1: DIAGNOSTIC ═══');
  await printDiagnosticSummary(db);

  print('\n═══ STEP 2: CLEANUP ═══');
  await cleanupOrphanDuplicateLessons(db);
  await cleanupOrphanDuplicateExams(db);

  print('\n✅ Full cleanup complete.');
}
