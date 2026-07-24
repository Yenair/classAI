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
}
