// lib/core/database/daos/scheme_of_work_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/scheme_of_work.dart';

part 'scheme_of_work_dao.g.dart';

@DriftAccessor(tables: [SchemeOfWork])
class SchemeOfWorkDao extends DatabaseAccessor<AppDatabase>
    with _$SchemeOfWorkDaoMixin {
  SchemeOfWorkDao(AppDatabase db) : super(db);

  Future<List<SchemeOfWorkData>> getAll() {
    return (select(schemeOfWork)
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  Future<List<SchemeOfWorkData>> getBySchool(int schoolId) {
    return (select(schemeOfWork)
          ..where((t) => t.schoolId.equals(schoolId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  Future<List<SchemeOfWorkData>> getByTeacher(int teacherId) {
    return (select(schemeOfWork)
          ..where((t) => t.teacherId.equals(teacherId))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  Future<List<SchemeOfWorkData>> getSaved() {
    return (select(schemeOfWork)
          ..where((t) => t.status.equals('rejected').not())
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt, mode: OrderingMode.desc)]))
        .get();
  }

  Future<List<SchemeOfWorkData>> getSavedBySubject(int subjectId) {
    return (select(schemeOfWork)
          ..where((t) => t.status.equals('rejected').not())
          ..where((t) => t.subjectId.equals(subjectId))
          ..orderBy([(t) => OrderingTerm(expression: t.weekNumber, mode: OrderingMode.asc)]))
        .get();
  }

  Future<SchemeOfWorkData?> getById(int id) async {
    final results = await (select(schemeOfWork)
          ..where((t) => t.id.equals(id)))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> insert(SchemeOfWorkCompanion companion) {
    return into(schemeOfWork).insert(companion);
  }

  Future<void> updateStatus(int id, String status, {String? adminComment}) {
    return (update(schemeOfWork)..where((t) => t.id.equals(id))).write(
      SchemeOfWorkCompanion(
        status: Value(status),
        adminComment: adminComment != null
            ? Value(adminComment)
            : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateAdminEditedTopic(int id, String topic) {
    return (update(schemeOfWork)..where((t) => t.id.equals(id))).write(
      SchemeOfWorkCompanion(
        adminEditedTopic: Value(topic),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<void> updateWeekEntry(
    int id, {
    String? topic,
    String? objectives,
  }) {
    return (update(schemeOfWork)..where((t) => t.id.equals(id))).write(
      SchemeOfWorkCompanion(
        topic: topic != null ? Value(topic) : const Value.absent(),
        objectives:
            objectives != null ? Value(objectives) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Finds the first active, non-deleted row matching the scheme_of_work
  /// natural key. Returns null when no match exists.
  Future<SchemeOfWorkData?> getByNaturalKey({
    required int schoolId,
    required int teacherId,
    required int subjectId,
    required String term,
    required int weekNumber,
  }) async {
    final results = await (select(schemeOfWork)
          ..where((t) =>
              t.schoolId.equals(schoolId) &
              t.teacherId.equals(teacherId) &
              t.subjectId.equals(subjectId) &
              t.term.equals(term) &
              t.weekNumber.equals(weekNumber) &
              t.isDeleted.equals(false))
          ..limit(1))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Returns groups of active rows that share the same non-empty serverId.
  /// Each inner list has length > 1. Empty when no duplicates exist.
  Future<List<List<SchemeOfWorkData>>> findDuplicateServerIdGroups() async {
    final dupRows = await (customSelect(
      'SELECT server_id, COUNT(*) AS cnt '
      'FROM scheme_of_work '
      'WHERE server_id IS NOT NULL AND server_id != \'\' '
      'AND is_deleted = 0 '
      'GROUP BY server_id '
      'HAVING COUNT(*) > 1',
    ))
        .get();
    if (dupRows.isEmpty) return const [];
    final groups = <List<SchemeOfWorkData>>[];
    for (final row in dupRows) {
      final sid = row.data['server_id'] as String;
      final rows = await (select(schemeOfWork)
            ..where((t) =>
                t.serverId.equals(sid) & t.isDeleted.equals(false))
            ..orderBy([(t) => OrderingTerm(expression: t.id)]))
          .get();
      if (rows.length > 1) groups.add(rows);
    }
    return groups;
  }

  /// Hard-deletes [deleteIds] from scheme_of_work.
  /// Caller must handle orphan queue entries and version_hashes.
  Future<void> mergeAndDeleteGroup({
    required List<int> deleteIds,
  }) async {
    if (deleteIds.isEmpty) return;
    await (delete(schemeOfWork)
          ..where((t) => t.id.isIn(deleteIds)))
        .go();
  }

  /// Hard-delete only confirmed-synced rows for a given teacher.
  /// Used during logout to scope-clean the outgoing teacher's data
  /// while leaving unsynced (pending) rows intact (Option b).
  /// [teacherLocalId] is the integer FK into Teachers.localId.
  Future<void> deleteSyncedRowsByTeacher(int teacherLocalId) {
    return (delete(schemeOfWork)
          ..where((t) => t.teacherId.equals(teacherLocalId))
          ..where((t) => t.serverId.isNotNull()))
        .go();
  }

  /// Hard-delete a single scheme row. Used by the "Plan My Term" recreate
  /// flow AFTER the row's linked draft lessons/exams have been soft-deleted
  /// and DELETE sync entries queued.
  Future<void> hardDelete(int id) {
    return (delete(schemeOfWork)..where((t) => t.id.equals(id))).go();
  }
}
