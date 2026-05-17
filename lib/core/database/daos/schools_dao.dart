// lib/core/database/daos/schools_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/schools.dart';

part 'schools_dao.g.dart';

@DriftAccessor(tables: [Schools])
class SchoolsDao extends DatabaseAccessor<AppDatabase>
    with _$SchoolsDaoMixin {
  SchoolsDao(AppDatabase db) : super(db);

  /// Get the school record.
  Future<School?> get() async {
    final results = await (select(schools)
          ..where((t) => t.isDeleted.equals(false))
          ..limit(1))
        .get();
    return results.isNotEmpty ? results.first : null;
  }

  /// Get the school by local ID.
  Future<School?> getByLocalId(int localId) async {
    final results = await (select(schools)
          ..where((t) => t.localId.equals(localId)))
        .get();
    return results.isNotEmpty ? results.first : null;
  }
}
