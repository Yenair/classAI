// lib/features/admin/screens/admin_diagnostics_screen.dart
//
// Read-only admin diagnostics screen. Queries the local Drift database only.
// No sync, no Supabase, no SharedPreferences, no inserts/updates/deletes.

import 'dart:io' show Platform;

import 'package:drift/drift.dart' hide Column;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/features/auth/providers/auth_provider.dart';
import 'package:classai/main.dart' show databaseProvider;

/// ─── Data models ───────────────────────────────────────────────────────

class _DiagnosticsData {
  final int localLessonCount;
  final int localExamCount;
  final int localOnlyLessonCount;
  final int localOnlyExamCount;
  final List<_DuplicateEntry> duplicateLessons;
  final List<_DuplicateEntry> duplicateExams;
  final int duplicateLessonsCount;
  final int duplicateExamsCount;
  final _SyncQueueSummary syncQueue;
  final List<_TeacherSummary> teacherSummaries;
  final _TeacherIdSummary currentTeacherLessonIds;
  final _TeacherIdSummary currentTeacherExamIds;
  final List<_ServerIdGroup> lessonServerIdGroups;
  final List<_ServerIdGroup> examServerIdGroups;
  /// Count of active lessons with the specific test server_id + teacher_server_id
  /// that the admin cleanup button targets.
  final int testDuplicateLessonCount;

  final List<_DuplicateEntry> duplicateSchemes;
  final int duplicateSchemeCount;
  final int localSchemeCount;
  final int localOnlySchemeCount;
  final List<_ServerIdGroup> schemeServerIdGroups;

  const _DiagnosticsData({
    required this.localLessonCount,
    required this.localExamCount,
    required this.localOnlyLessonCount,
    required this.localOnlyExamCount,
    required this.duplicateLessons,
    required this.duplicateExams,
    required this.duplicateLessonsCount,
    required this.duplicateExamsCount,
    required this.syncQueue,
    required this.teacherSummaries,
    required this.currentTeacherLessonIds,
    required this.currentTeacherExamIds,
    required this.lessonServerIdGroups,
    required this.examServerIdGroups,
    required this.testDuplicateLessonCount,
    required this.duplicateSchemes,
    required this.duplicateSchemeCount,
    required this.localSchemeCount,
    required this.localOnlySchemeCount,
    required this.schemeServerIdGroups,
  });
}

class _DuplicateEntry {
  final String serverId;
  final int count;
  const _DuplicateEntry({required this.serverId, required this.count});
}

class _SyncQueueItem {
  final String operation;
  final int count;
  const _SyncQueueItem({required this.operation, required this.count});
}

class _SyncQueueSummary {
  final int lessonCount;
  final int examCount;
  final List<_SyncQueueItem> lessonOperations;
  final List<_SyncQueueItem> examOperations;
  final int schemeOfWorkCount;
  final List<_SyncQueueItem> schemeOfWorkOperations;
  const _SyncQueueSummary({
    required this.lessonCount,
    required this.examCount,
    required this.lessonOperations,
    required this.examOperations,
    required this.schemeOfWorkCount,
    required this.schemeOfWorkOperations,
  });
}

class _TeacherSummary {
  final String teacherServerId;
  final int totalActiveLessons;
  final int localOnlyLessons;
  final int deletedLessons;
  final int totalActiveExams;
  final int localOnlyExams;
  final int deletedExams;
  const _TeacherSummary({
    required this.teacherServerId,
    required this.totalActiveLessons,
    required this.localOnlyLessons,
    required this.deletedLessons,
    required this.totalActiveExams,
    required this.localOnlyExams,
    required this.deletedExams,
  });
}

class _TeacherIdSummary {
  final int totalActive;
  final int noServerId;
  final int hasServerId;
  final int distinctServerIds;
  const _TeacherIdSummary({
    required this.totalActive,
    required this.noServerId,
    required this.hasServerId,
    required this.distinctServerIds,
  });
}

class _ServerIdGroup {
  final String displayLabel;
  final int localRowCount;
  final List<String> teacherServerIds;
  final List<String> subjects;
  final List<String> classLevels;
  final DateTime earliestCreated;
  final DateTime latestCreated;
  const _ServerIdGroup({
    required this.displayLabel,
    required this.localRowCount,
    required this.teacherServerIds,
    required this.subjects,
    required this.classLevels,
    required this.earliestCreated,
    required this.latestCreated,
  });
}

/// ─── Helpers ───────────────────────────────────────────────────────────

bool _isNullOrEmpty(String? s) => s == null || s.isEmpty;

String _joinUnique(List<String> items) {
  final unique = items.toSet().toList()..sort();
  if (unique.isEmpty) return '—';
  if (unique.length == 1) return unique.first;
  return unique.join(', ');
}

String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

_TeacherIdSummary _buildTeacherIdSummary(List<dynamic> rows, bool isLesson) {
  int noServerId = 0;
  int hasServerId = 0;
  final distinctIds = <String>{};
  for (final r in rows) {
    final sid = isLesson
        ? (r as Lesson).serverId
        : (r as Exam).serverId;
    if (_isNullOrEmpty(sid)) {
      noServerId++;
    } else {
      hasServerId++;
      distinctIds.add(sid!);
    }
  }
  return _TeacherIdSummary(
    totalActive: rows.length,
    noServerId: noServerId,
    hasServerId: hasServerId,
    distinctServerIds: distinctIds.length,
  );
}

List<_ServerIdGroup> _buildServerIdGroups(List<dynamic> rows, bool isLesson) {
  final map = <String, List<dynamic>>{};
  for (final r in rows) {
    final sid = isLesson
        ? (r as Lesson).serverId
        : (r as Exam).serverId;
    final key = _isNullOrEmpty(sid) ? '(no server ID)' : sid!;
    map.putIfAbsent(key, () => []).add(r);
  }

  final groups = <_ServerIdGroup>[];
  for (final entry in map.entries) {
    final items = entry.value;
    DateTime earliest = DateTime(9999);
    DateTime latest = DateTime(0);
    final teachers = <String>{};
    final subjects = <String>{};
    final classLevels = <String>{};

    for (final r in items) {
      late final DateTime createdAt;
      late final String? teacherSid;
      late final String subject;
      late final String classLevel;
      if (isLesson) {
        final l = r as Lesson;
        createdAt = l.createdAt;
        teacherSid = l.teacherServerId;
        subject = l.subject;
        classLevel = l.classLevel;
      } else {
        final e = r as Exam;
        createdAt = e.createdAt;
        teacherSid = e.teacherServerId;
        subject = e.subject;
        classLevel = e.classLevel;
      }
      if (createdAt.isBefore(earliest)) earliest = createdAt;
      if (createdAt.isAfter(latest)) latest = createdAt;
      teachers.add(teacherSid ?? '(no teacher)');
      subjects.add(subject);
      classLevels.add(classLevel);
    }

    groups.add(_ServerIdGroup(
      displayLabel: entry.key,
      localRowCount: items.length,
      teacherServerIds: teachers.toList(),
      subjects: subjects.toList(),
      classLevels: classLevels.toList(),
      earliestCreated: earliest,
      latestCreated: latest,
    ));
  }

  groups.sort((a, b) => b.localRowCount.compareTo(a.localRowCount));
  return groups;
}

List<_ServerIdGroup> _buildSchemeServerIdGroups(List<SchemeOfWorkData> rows) {
  final map = <String, List<SchemeOfWorkData>>{};
  for (final r in rows) {
    final sid = r.serverId;
    final key = _isNullOrEmpty(sid) ? '(no server ID)' : sid!;
    map.putIfAbsent(key, () => []).add(r);
  }

  final groups = <_ServerIdGroup>[];
  for (final entry in map.entries) {
    final items = entry.value;
    DateTime earliest = DateTime(9999);
    DateTime latest = DateTime(0);
    final classLevels = <String>{};

    for (final r in items) {
      if (r.createdAt.isBefore(earliest)) earliest = r.createdAt;
      if (r.createdAt.isAfter(latest)) latest = r.createdAt;
      classLevels.add(r.classLevel);
    }

    groups.add(_ServerIdGroup(
      displayLabel: entry.key,
      localRowCount: items.length,
      teacherServerIds: const ['—'],
      subjects: const ['—'],
      classLevels: classLevels.toList(),
      earliestCreated: earliest,
      latestCreated: latest,
    ));
  }

  groups.sort((a, b) => b.localRowCount.compareTo(a.localRowCount));
  return groups;
}

/// ─── Provider ──────────────────────────────────────────────────────────

final diagnosticsProvider =
    FutureProvider.autoDispose<_DiagnosticsData>((ref) async {
  final db = ref.read(databaseProvider);
  final authData = ref.read(authProvider);

  final teacherServerId = authData.currentTeacher?.serverId;
  final schoolServerId = authData.currentSchool?.serverId;

  const emptyIdSummary = _TeacherIdSummary(
      totalActive: 0, noServerId: 0, hasServerId: 0, distinctServerIds: 0);

  if (teacherServerId == null || schoolServerId == null) {
    return const _DiagnosticsData(
      localLessonCount: 0,
      localExamCount: 0,
      localOnlyLessonCount: 0,
      localOnlyExamCount: 0,
      duplicateLessons: [],
      duplicateExams: [],
      duplicateLessonsCount: 0,
      duplicateExamsCount: 0,
      syncQueue: _SyncQueueSummary(
          lessonCount: 0,
          examCount: 0,
          lessonOperations: [],
          examOperations: [],
          schemeOfWorkCount: 0,
          schemeOfWorkOperations: []),
      teacherSummaries: [],
      currentTeacherLessonIds: emptyIdSummary,
      currentTeacherExamIds: emptyIdSummary,
      lessonServerIdGroups: [],
      examServerIdGroups: [],
      testDuplicateLessonCount: 0,
      duplicateSchemes: [],
      duplicateSchemeCount: 0,
      localSchemeCount: 0,
      localOnlySchemeCount: 0,
      schemeServerIdGroups: [],
    );
  }

  // ── 1. Local lesson count (teacher+school, active)
  final lessonRows = await (db.select(db.lessons)
        ..where((t) =>
            t.teacherServerId.equals(teacherServerId) &
            t.schoolServerId.equals(schoolServerId) &
            t.isDeleted.equals(false)))
      .get();

  // ── 2. Local exam count (teacher+school, active)
  final examRows = await (db.select(db.exams)
        ..where((t) =>
            t.teacherServerId.equals(teacherServerId) &
            t.schoolServerId.equals(schoolServerId) &
            t.isDeleted.equals(false)))
      .get();

  // ── 3. Local-only lessons (school, active, no server_id)
  final localOnlyLessons = await (db.select(db.lessons)
        ..where((t) =>
            t.schoolServerId.equals(schoolServerId) &
            t.isDeleted.equals(false) &
            (t.serverId.isNull() | t.serverId.equals(''))))
      .get();

  // ── 4. Local-only exams (school, active, no server_id)
  final localOnlyExams = await (db.select(db.exams)
        ..where((t) =>
            t.schoolServerId.equals(schoolServerId) &
            t.isDeleted.equals(false) &
            (t.serverId.isNull() | t.serverId.equals(''))))
      .get();

  // ── 5. Duplicate lessons (active, non-empty server_id, count > 1)
  final dupLessonRows = await db.customSelect(
    'SELECT server_id, COUNT(*) AS cnt '
    'FROM lessons '
    'WHERE is_deleted = 0 '
    'AND server_id IS NOT NULL AND server_id != \'\' '
    'GROUP BY server_id '
    'HAVING COUNT(*) > 1',
  ).get();
  final dupLessons = dupLessonRows
      .map((r) => _DuplicateEntry(
          serverId: r.data['server_id'] as String,
          count: r.data['cnt'] as int))
      .toList();

  // ── 6. Duplicate exams (active, non-empty server_id, count > 1)
  final dupExamRows = await db.customSelect(
    'SELECT server_id, COUNT(*) AS cnt '
    'FROM exams '
    'WHERE is_deleted = 0 '
    'AND server_id IS NOT NULL AND server_id != \'\' '
    'GROUP BY server_id '
    'HAVING COUNT(*) > 1',
  ).get();
  final dupExams = dupExamRows
      .map((r) => _DuplicateEntry(
          serverId: r.data['server_id'] as String,
          count: r.data['cnt'] as int))
      .toList();

  // ── 7. Pending sync queue (non-terminal, grouped)
  final pendingQueue = await (db.select(db.syncQueue)
        ..where((t) => t.isTerminal.equals(false)))
      .get();
  final lessonQueue =
      pendingQueue.where((t) => t.queueTable == 'lessons').toList();
  final examQueue =
      pendingQueue.where((t) => t.queueTable == 'exams').toList();

  Map<String, int> _groupOps(List<SyncQueueData> rows) {
    final map = <String, int>{};
    for (final r in rows) {
      map[r.operation] = (map[r.operation] ?? 0) + 1;
    }
    return map;
  }

  final lessonOps = _groupOps(lessonQueue);
  final examOps = _groupOps(examQueue);
  final schemeQueue =
      pendingQueue.where((t) => t.queueTable == 'scheme_of_work').toList();
  final schemeOps = _groupOps(schemeQueue);

  // ── 8. Duplicate scheme_of_work (active, non-empty server_id, count > 1)
  final dupSchemeRows = await db.customSelect(
    'SELECT server_id, COUNT(*) AS cnt '
    'FROM scheme_of_work '
    'WHERE is_deleted = 0 '
    'AND server_id IS NOT NULL AND server_id != \'\' '
    'GROUP BY server_id '
    'HAVING COUNT(*) > 1',
  ).get();
  final dupSchemes = dupSchemeRows
      .map((r) => _DuplicateEntry(
          serverId: r.data['server_id'] as String,
          count: r.data['cnt'] as int))
      .toList();

  // ── 9. scheme_of_work local counts
  final allSchemes = await (db.select(db.schemeOfWork)
        ..where((t) => t.isDeleted.equals(false)))
      .get();
  final school = await db.schoolsDao.getByServerId(schoolServerId);
  final schoolLocalId = school?.localId;
  final schoolSchemes = schoolLocalId != null
      ? allSchemes.where((r) => r.schoolId == schoolLocalId).toList()
      : <SchemeOfWorkData>[];
  final localOnlySchemes = schoolSchemes
      .where((r) => r.serverId == null || r.serverId!.isEmpty)
      .toList();

  // ── 10. Counts by teacher (school-wide)
  final allLessons = await (db.select(db.lessons)
        ..where((t) => t.schoolServerId.equals(schoolServerId)))
      .get();
  final allExams = await (db.select(db.exams)
        ..where((t) => t.schoolServerId.equals(schoolServerId)))
      .get();

  final lessonByTeacher = <String, List<Lesson>>{};
  for (final l in allLessons) {
    final tsid = l.teacherServerId ?? '(no teacher)';
    lessonByTeacher.putIfAbsent(tsid, () => []).add(l);
  }
  final examByTeacher = <String, List<Exam>>{};
  for (final e in allExams) {
    final tsid = e.teacherServerId ?? '(no teacher)';
    examByTeacher.putIfAbsent(tsid, () => []).add(e);
  }

  final allTeacherIds = <String>{
    ...lessonByTeacher.keys,
    ...examByTeacher.keys,
  };

  final teacherSummaries = <_TeacherSummary>[];
  for (final tsid in allTeacherIds) {
    final ls = lessonByTeacher[tsid] ?? [];
    final es = examByTeacher[tsid] ?? [];

    teacherSummaries.add(_TeacherSummary(
      teacherServerId: tsid,
      totalActiveLessons: ls.where((l) => !l.isDeleted).length,
      localOnlyLessons: ls
          .where((l) =>
              !l.isDeleted && (l.serverId == null || l.serverId == ''))
          .length,
      deletedLessons: ls.where((l) => l.isDeleted).length,
      totalActiveExams: es.where((e) => !e.isDeleted).length,
      localOnlyExams: es
          .where((e) =>
              !e.isDeleted && (e.serverId == null || e.serverId == ''))
          .length,
      deletedExams: es.where((e) => e.isDeleted).length,
    ));
  }

  teacherSummaries.sort(
      (a, b) => (b.totalActiveLessons + b.totalActiveExams)
          .compareTo(a.totalActiveLessons + a.totalActiveExams));

  // ── 9. Current teacher lesson/exam ID summaries
  final currentTeacherLessonIds = _buildTeacherIdSummary(lessonRows, true);
  final currentTeacherExamIds = _buildTeacherIdSummary(examRows, false);

  // ── 10. Lesson & exam server_id groups (school-wide)
  final lessonServerIdGroups = _buildServerIdGroups(allLessons, true);
  final examServerIdGroups = _buildServerIdGroups(allExams, false);

  // ── 11. Count of old test lessons targeted by the cleanup button
  const _testTeacherId = '4e569a31-99d1-44a6-8bcc-4efbf0d67a71';
  final testDupRows = await (db.select(db.lessons)
        ..where((t) =>
            t.teacherServerId.equals(_testTeacherId) &
            t.topic.equals('direct test topic') &
            t.subject.equals('_test_e2e_direct') &
            t.isDeleted.equals(false)))
      .get();

  return _DiagnosticsData(
    localLessonCount: lessonRows.length,
    localExamCount: examRows.length,
    localOnlyLessonCount: localOnlyLessons.length,
    localOnlyExamCount: localOnlyExams.length,
    duplicateLessons: dupLessons,
    duplicateExams: dupExams,
    duplicateLessonsCount:
        dupLessons.fold(0, (sum, d) => sum + d.count),
    duplicateExamsCount:
        dupExams.fold(0, (sum, d) => sum + d.count),
    syncQueue: _SyncQueueSummary(
      lessonCount: lessonQueue.length,
      examCount: examQueue.length,
      lessonOperations: lessonOps.entries
          .map((e) => _SyncQueueItem(operation: e.key, count: e.value))
          .toList(),
      examOperations: examOps.entries
          .map((e) => _SyncQueueItem(operation: e.key, count: e.value))
          .toList(),
      schemeOfWorkCount: schemeQueue.length,
      schemeOfWorkOperations: schemeOps.entries
          .map((e) => _SyncQueueItem(operation: e.key, count: e.value))
          .toList(),
    ),
    teacherSummaries: teacherSummaries,
    currentTeacherLessonIds: currentTeacherLessonIds,
    currentTeacherExamIds: currentTeacherExamIds,
    lessonServerIdGroups: lessonServerIdGroups,
    examServerIdGroups: examServerIdGroups,
    testDuplicateLessonCount: testDupRows.length,
    duplicateSchemes: dupSchemes,
    duplicateSchemeCount:
        dupSchemes.fold(0, (sum, d) => sum + d.count),
    localSchemeCount: schoolSchemes.length,
    localOnlySchemeCount: localOnlySchemes.length,
    schemeServerIdGroups: _buildSchemeServerIdGroups(schoolSchemes),
  );
});

/// ─── Screen ─────────────────────────────────────────────────────────────

class AdminDiagnosticsScreen extends ConsumerStatefulWidget {
  const AdminDiagnosticsScreen({super.key});

  @override
  ConsumerState<AdminDiagnosticsScreen> createState() =>
      _AdminDiagnosticsScreenState();
}

class _AdminDiagnosticsScreenState
    extends ConsumerState<AdminDiagnosticsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.invalidate(diagnosticsProvider);
    });
  }

  // ── Test-lesson cleanup ──────────────────────────────────────────
  // Matches all old direct-test lessons by teacher + topic + subject.
  static const _testTeacherId = '4e569a31-99d1-44a6-8bcc-4efbf0d67a71';

  /// Removes ALL active local lessons matching the old test-lesson criteria.
  ///
  /// For rows that have a server_id, a sync_queue DELETE entry is queued
  /// so the server row is also soft-deleted on the next push cycle.
  /// Does NOT call Supabase directly.
  Future<int> _removeTestDuplicateLessons() async {
    final db = ref.read(databaseProvider);
    final rows = await (db.select(db.lessons)
          ..where((t) =>
              t.teacherServerId.equals(_testTeacherId) &
              t.topic.equals('direct test topic') &
              t.subject.equals('_test_e2e_direct') &
              t.isDeleted.equals(false)))
        .get();
    if (rows.isEmpty) return 0;
    // For each row with a server_id, queue a sync DELETE so the server
    // row is soft-deleted on the next push cycle.
    for (final row in rows) {
      if (row.serverId != null && row.serverId!.isNotEmpty) {
        await db.syncQueueDao.insertEntry(
          queueTable: 'lessons',
          recordLocalId: row.id,
          operation: 'DELETE',
          payload: {'server_id': row.serverId},
        );
      }
    }
    final ids = rows.map((r) => r.id).toList();
    await (db.delete(db.lessons)
          ..where((t) => t.id.isIn(ids)))
        .go();
    return ids.length;
  }

  void _showTestDuplicateCleanupDialog() {
    final data = ref.read(diagnosticsProvider).value;
    final count = data?.testDuplicateLessonCount ?? 0;
    if (count == 0) return; // nothing to clean
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove test duplicates?'),
        content: const Text(
          'This will remove all old test copies of the direct test lesson. '
          'Real lesson work will not be touched. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final deleted = await _removeTestDuplicateLessons();
              if (!mounted) return;
              // Refresh diagnostics counts
              ref.invalidate(diagnosticsProvider);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Removed $deleted test lesson rows.')),
              );
            },
            child: const Text('Delete test lessons'),
          ),
        ],
      ),
    );
  }

  // ── Scheme-of-work duplicate merge ──────────────────────────────
  Future<int> _mergeSchemeDuplicates() async {
    final db = ref.read(databaseProvider);
    final groups = await db.schemeOfWorkDao.findDuplicateServerIdGroups();
    var totalDeleted = 0;
    for (final group in groups) {
      final canonicalId = group.first.id;
      final deleteIds = group.skip(1).map((r) => r.id).toList();
      // Mark orphan queue entries terminal
      for (final delId in deleteIds) {
        final orphans = await (db.select(db.syncQueue)
              ..where((t) =>
                  t.queueTable.equals('scheme_of_work') &
                  t.recordLocalId.equals(delId)))
            .get();
        for (final q in orphans) {
          await (db.update(db.syncQueue)
                ..where((t) => t.id.equals(q.id)))
              .write(SyncQueueCompanion(
            isTerminal: const Value(true),
            lastError: Value('Duplicate merged into canonical '
                'scheme_of_work id=$canonicalId'),
          ));
        }
        // Clean up version_hashes for deleted rows
        await (db.delete(db.versionHashes)
              ..where((t) =>
                  t.table.equals('scheme_of_work') &
                  t.recordLocalId.equals(delId)))
            .go();
      }
      // Hard-delete duplicate rows
      await db.schemeOfWorkDao.mergeAndDeleteGroup(
        deleteIds: deleteIds,
      );
      totalDeleted += deleteIds.length;
    }
    return totalDeleted;
  }

  void _showSchemeMergeDialog() {
    final data = ref.read(diagnosticsProvider).value;
    final count = data?.duplicateSchemeCount ?? 0;
    if (count == 0) return;
    final groupCount = data?.duplicateSchemes.length ?? 0;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merge duplicate scheme rows?'),
        content: Text(
          'This will merge $count duplicate scheme_of_work rows '
          'across $groupCount group(s).\n\n'
          'For each group the row with the lowest local ID is kept '
          'and newer non-empty fields from the other rows are merged '
          'into it. The duplicate rows are permanently deleted.\n\n'
          'No sync_queue DELETE entries will be created. '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              final deleted = await _mergeSchemeDuplicates();
              if (!mounted) return;
              ref.invalidate(diagnosticsProvider);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Merged and removed $deleted duplicate scheme rows.',
                  ),
                ),
              );
            },
            child: const Text('Merge duplicates'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final asyncData = ref.watch(diagnosticsProvider);

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('Diagnostics'),
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(diagnosticsProvider),
          ),
        ],
      ),
      floatingActionButton: asyncData.whenOrNull(
        data: (data) {
          if (data.duplicateSchemeCount > 0) {
            return FloatingActionButton.extended(
              onPressed: _showSchemeMergeDialog,
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
              icon: const Icon(Icons.merge_type_rounded),
              label: Text('Merge ${data.duplicateSchemeCount} duplicate scheme rows'),
            );
          }
          if (data.testDuplicateLessonCount > 0) {
            return FloatingActionButton.extended(
              onPressed: _showTestDuplicateCleanupDialog,
              backgroundColor: cs.errorContainer,
              foregroundColor: cs.onErrorContainer,
              icon: const Icon(Icons.delete_sweep_rounded),
              label: const Text('Remove all old test lessons'),
            );
          }
          return null;
        },
      ),
      body: asyncData.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('Failed to load diagnostics: $e',
                style: TextStyle(color: cs.error)),
          ),
        ),
        data: (data) => _buildBody(cs, textTheme, data),
      ),
    );
  }

  // ── Single SelectableText.rich body ───────────────────────────
  // Everything is ONE selectable text widget so Ctrl+A, Ctrl+C,
  // and drag-select all work across the entire page.

  Widget _buildBody(
    ColorScheme cs,
    TextTheme textTheme,
    _DiagnosticsData data,
  ) {
    final bgCard = Paint()..color = cs.surfaceContainerLow.withValues(alpha: 0.6);

    final headerStyle = textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: cs.primary,
    );
    final bigStyle = textTheme.headlineSmall?.copyWith(
      fontWeight: FontWeight.bold,
      color: cs.onSurface,
    );
    final hintStyle = textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final labelStyle = textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w500,
    );
    final valueStyle = textTheme.bodySmall?.copyWith(color: cs.onSurface);
    final cardLabelStyle = textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.bold,
      color: cs.onSurface,
    );

    final children = <InlineSpan>[
      // ── Local Lesson Count ─────────────────
      _h('Local Lesson Count', headerStyle),
      _v('${data.localLessonCount}', bigStyle),
      _h('Local Exam Count', headerStyle),
      _v('${data.localExamCount}', bigStyle),

      // ── Current teacher ID summaries ───────
      _h('Current Teacher Lesson IDs', headerStyle),
      _teacherIdSpan(data.currentTeacherLessonIds, labelStyle, valueStyle, bgCard),
      _h('Current Teacher Exam IDs', headerStyle),
      _teacherIdSpan(data.currentTeacherExamIds, labelStyle, valueStyle, bgCard),

      // ── Not yet synced ─────────────────────
      _h('Lessons Not Yet Synced', headerStyle),
      _v('${data.localOnlyLessonCount}', bigStyle),
      _hint('Active lessons in this school with no server ID.', hintStyle),
      _h('Exams Not Yet Synced', headerStyle),
      _v('${data.localOnlyExamCount}', bigStyle),
      _hint('Active exams in this school with no server ID.', hintStyle),

      // ── Duplicates ─────────────────────────
      _h('Duplicate Lessons', headerStyle),
      _v('${data.duplicateLessonsCount} rows across ${data.duplicateLessons.length} groups', bigStyle),
      if (data.duplicateLessons.isEmpty)
        _hint('No duplicates found.', hintStyle)
      else
        for (final d in data.duplicateLessons)
          _row(d.serverId, '${d.count} copies', labelStyle, valueStyle),

      _h('Duplicate Exams', headerStyle),
      _v('${data.duplicateExamsCount} rows across ${data.duplicateExams.length} groups', bigStyle),
      if (data.duplicateExams.isEmpty)
        _hint('No duplicates found.', hintStyle)
      else
        for (final d in data.duplicateExams)
          _row(d.serverId, '${d.count} copies', labelStyle, valueStyle),

      // ── Lesson Server ID Groups ────────────
      _h('Lesson Server ID Groups', headerStyle),
      ..._serverIdGroupSpans(data.lessonServerIdGroups, cardLabelStyle, labelStyle, valueStyle, bgCard),

      // ── Exam Server ID Groups ──────────────
      _h('Exam Server ID Groups', headerStyle),
      ..._serverIdGroupSpans(data.examServerIdGroups, cardLabelStyle, labelStyle, valueStyle, bgCard),

      // ── Scheme-of-Work Duplicates ────────────
      _h('Duplicate Scheme-of-Work', headerStyle),
      _v('${data.duplicateSchemeCount} rows across '
          '${data.duplicateSchemes.length} groups', bigStyle),
      if (data.duplicateSchemes.isEmpty)
        _hint('No duplicates found.', hintStyle)
      else
        for (final d in data.duplicateSchemes)
          _row(d.serverId, '${d.count} copies', labelStyle, valueStyle),

      _h('Local Scheme-of-Work Count', headerStyle),
      _v('${data.localSchemeCount}', bigStyle),
      _h('Scheme-of-Work Not Yet Synced', headerStyle),
      _v('${data.localOnlySchemeCount}', bigStyle),

      // ── Scheme-of-Work Server ID Groups ─────
      _h('Scheme-of-Work Server ID Groups', headerStyle),
      ..._serverIdGroupSpans(data.schemeServerIdGroups, cardLabelStyle, labelStyle, valueStyle, bgCard),

      // ── Pending Sync Queue ─────────────────
      _h('Pending Sync Queue', headerStyle),
      _v('${data.syncQueue.lessonCount + data.syncQueue.examCount + data.syncQueue.schemeOfWorkCount} items waiting', bigStyle),
      _hint('Lessons: ${data.syncQueue.lessonCount}', hintStyle),
      for (final op in data.syncQueue.lessonOperations)
        _row('  ${op.operation}', '${op.count}', labelStyle, valueStyle),
      _hint('Exams: ${data.syncQueue.examCount}', hintStyle),
      for (final op in data.syncQueue.examOperations)
        _row('  ${op.operation}', '${op.count}', labelStyle, valueStyle),
      _hint('Scheme-of-Work: ${data.syncQueue.schemeOfWorkCount}', hintStyle),
      for (final op in data.syncQueue.schemeOfWorkOperations)
        _row('  ${op.operation}', '${op.count}', labelStyle, valueStyle),

      // ── Counts by Teacher ──────────────────
      _h('Counts by Teacher', headerStyle),
      if (data.teacherSummaries.isEmpty)
        _hint('No teachers found for this school.', hintStyle)
      else
        for (final t in data.teacherSummaries)
          ..._teacherSummarySpans(t, cardLabelStyle, labelStyle, valueStyle, bgCard),
    ];

    return SingleChildScrollView(
      physics: (Platform.isAndroid || Platform.isIOS)
          ? const BouncingScrollPhysics()
          : const ClampingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: SizedBox(
        width: double.infinity,
        child: SelectableText.rich(
          TextSpan(children: children),
          textAlign: TextAlign.left,
          style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
        ),
      ),
    );
  }

  // ── Span helpers ──────────────────────────────────────────────

  InlineSpan _h(String text, TextStyle? style) => TextSpan(
        text: '\n\n$text\n',
        style: style,
      );

  InlineSpan _v(String text, TextStyle? style) => TextSpan(
        text: '$text\n',
        style: style,
      );

  InlineSpan _hint(String text, TextStyle? style) => TextSpan(
        text: '$text\n',
        style: style,
      );

  InlineSpan _row(String label, String value, TextStyle? labelStyle, TextStyle? valueStyle) {
    return TextSpan(
      children: [
        TextSpan(text: '  $label: ', style: labelStyle),
        TextSpan(text: '$value\n', style: valueStyle),
      ],
    );
  }

  InlineSpan _teacherIdSpan(
      _TeacherIdSummary s, TextStyle? labelStyle, TextStyle? valueStyle, Paint bg) {
    return TextSpan(
      style: TextStyle(background: bg),
      children: [
        TextSpan(text: '  Total active: ${s.totalActive}\n', style: valueStyle),
        TextSpan(text: '  No server ID: ${s.noServerId}\n', style: valueStyle),
        TextSpan(text: '  Has server ID: ${s.hasServerId}\n', style: valueStyle),
        TextSpan(text: '  Distinct IDs: ${s.distinctServerIds}\n', style: valueStyle),
      ],
    );
  }

  List<InlineSpan> _serverIdGroupSpans(
      List<_ServerIdGroup> groups,
      TextStyle? cardLabelStyle,
      TextStyle? labelStyle,
      TextStyle? valueStyle,
      Paint bg) {
    if (groups.isEmpty) {
      return [_hint('No active entries found.', labelStyle)];
    }

    final totalRows = groups.fold(0, (sum, g) => sum + g.localRowCount);
    const displayLimit = 20;
    final showing = groups.take(displayLimit).toList();
    final hidden = groups.length - showing.length;

    final spans = <InlineSpan>[
      _v('$totalRows rows across ${groups.length} groups', valueStyle),
    ];

    for (final g in showing) {
      spans.add(TextSpan(
        style: TextStyle(background: bg),
        children: [
          TextSpan(text: '\n  ${g.displayLabel}\n', style: cardLabelStyle),
          _row('    Local rows', '${g.localRowCount}', labelStyle, valueStyle),
          _row('    Teacher(s)', _joinUnique(g.teacherServerIds), labelStyle, valueStyle),
          _row('    Subject(s)', _joinUnique(g.subjects), labelStyle, valueStyle),
          _row('    Class level(s)', _joinUnique(g.classLevels), labelStyle, valueStyle),
          _row('    Earliest', _fmtDate(g.earliestCreated), labelStyle, valueStyle),
          _row('    Latest', _fmtDate(g.latestCreated), labelStyle, valueStyle),
        ],
      ));
    }

    if (hidden > 0) {
      spans.add(_hint('… and $hidden more groups not shown.', labelStyle));
    }
    return spans;
  }

  List<InlineSpan> _teacherSummarySpans(
      _TeacherSummary t,
      TextStyle? cardLabelStyle,
      TextStyle? labelStyle,
      TextStyle? valueStyle,
      Paint bg) {
    return [
      TextSpan(
        style: TextStyle(background: bg),
        children: [
          TextSpan(text: '\n  ${t.teacherServerId}\n', style: cardLabelStyle),
          _row('    Total active', '${t.totalActiveLessons} lessons, ${t.totalActiveExams} exams', labelStyle, valueStyle),
          _row('    Not yet synced', '${t.localOnlyLessons} lessons, ${t.localOnlyExams} exams', labelStyle, valueStyle),
          _row('    Deleted', '${t.deletedLessons} lessons, ${t.deletedExams} exams', labelStyle, valueStyle),
        ],
      ),
    ];
  }
}
