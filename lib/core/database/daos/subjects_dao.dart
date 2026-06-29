// lib/core/database/daos/subjects_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/subjects.dart';

part 'subjects_dao.g.dart';

@DriftAccessor(tables: [Subjects])
class SubjectsDao extends DatabaseAccessor<AppDatabase>
    with _$SubjectsDaoMixin {
  SubjectsDao(AppDatabase db) : super(db);

  /// Get all subjects.
  Future<List<Subject>> getAll() {
    return (select(subjects)
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc)]))
        .get();
  }

  /// Get a subject by name (case-insensitive search).
  Future<Subject?> getByName(String name) async {
    final results = await (select(subjects)
          ..where((t) => t.name.equals(name)))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Get a subject by its local ID.
  Future<Subject?> getById(int id) async {
    final results = await (select(subjects)..where((t) => t.id.equals(id))).get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Get subjects matching a search query.
  Future<List<Subject>> search(String query) {
    return (select(subjects)
          ..where((t) => t.name.contains(query))
          ..orderBy([(t) => OrderingTerm(expression: t.sortOrder, mode: OrderingMode.asc)]))
        .get();
  }

  /// Insert a subject.
  Future<int> insert({
    String? serverId,
    required String name,
    String? alias,
    String? schoolId,
    int sortOrder = 0,
  }) async {
    return into(subjects).insert(
      SubjectsCompanion.insert(
        serverId: serverId != null ? Value(serverId) : const Value.absent(),
        name: name,
        alias: alias != null ? Value(alias) : const Value.absent(),
        schoolId: schoolId != null ? Value(schoolId) : const Value.absent(),
        sortOrder: Value(sortOrder),
      ),
    );
  }
}
