// lib/core/database/repair_orphaned_scheme_links.dart
//
// One-time local repair for lessons/exams whose `schemeOfWorkId` points to a
// local Drift integer id that no longer exists in the `scheme_of_work` table
// (orphaned link). Such rows currently render as "scheme of work no longer
// available" in the editors.
//
// NOTE: This file defines the repair function only. It is wired to auto-run
// once (fire-and-forget) from the database bootstrapper in main.dart.
import 'package:shared_preferences/shared_preferences.dart';

import 'database.dart';

/// SharedPreferences key marking that the orphaned-scheme-link repair has
/// already run on this device, so it only runs once.
const String repairOrphanedSchemeLinksDoneKey =
    'repair_orphaned_scheme_links_done';

/// Scans all non-deleted lessons and exams, and for any whose `schemeOfWorkId`
/// parses to a local integer that does not exist in the local `scheme_of_work`
/// table, clears (nulls) that link so the row becomes fully editable again.
///
/// Returns the total number of cleared links (lessons + exams). Uses a single
/// transaction so the repair is atomic. Respects a run-once flag stored in
/// SharedPreferences; pass [force] = true to bypass it.
Future<int> repairOrphanedSchemeLinks(
  AppDatabase db, {
  bool force = false,
}) async {
  final prefs = await SharedPreferences.getInstance();
  if (!force && (prefs.getBool(repairOrphanedSchemeLinksDoneKey) ?? false)) {
    return 0;
  }

  // Snapshot of all local scheme ids that actually exist.
  final existingSchemeIds = (await db.schemeOfWorkDao.getAll())
      .map((s) => s.id)
      .toSet();

  int cleared = 0;

  await db.transaction(() async {
    final lessons = await db.lessonsDao.getAll();
    for (final lesson in lessons) {
      if (_isOrphaned(lesson.schemeOfWorkId, existingSchemeIds)) {
        await db.lessonsDao.clearSchemeOfWorkId(lesson.id);
        cleared++;
      }
    }

    final exams = await db.examsDao.getAll();
    for (final exam in exams) {
      if (_isOrphaned(exam.schemeOfWorkId, existingSchemeIds)) {
        await db.examsDao.clearSchemeOfWorkId(exam.id);
        cleared++;
      }
    }
  });

  await prefs.setBool(repairOrphanedSchemeLinksDoneKey, true);
  return cleared;
}

/// Returns true when [value] is a non-null string that parses to an integer
/// which is NOT present in [existingSchemeIds].
bool _isOrphaned(String? value, Set<int> existingSchemeIds) {
  if (value == null || value.isEmpty) return false;
  final parsed = int.tryParse(value);
  if (parsed == null) return false;
  return !existingSchemeIds.contains(parsed);
}
