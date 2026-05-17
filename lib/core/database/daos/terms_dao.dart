import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/terms.dart';

part 'terms_dao.g.dart';

@DriftAccessor(tables: [Terms])
class TermsDao extends DatabaseAccessor<AppDatabase>
    with _$TermsDaoMixin {
  TermsDao(AppDatabase db) : super(db);

  /// Insert a new term.
  Future<int> insert(TermsCompanion companion) {
    return into(terms).insert(companion);
  }

  /// Get all terms for a school, ordered by start_date ascending.
  Future<List<Term>> getBySchool(int schoolLocalId) {
    return (select(terms)
          ..where((t) => t.schoolLocalId.equals(schoolLocalId))
          ..orderBy([
            (t) => OrderingTerm(
                expression: t.startDate, mode: OrderingMode.asc)
          ]))
        .get();
  }

  /// Get the current active term for a school.
  Future<Term?> getCurrent(int schoolLocalId) async {
    final results = await (select(terms)
          ..where((t) =>
              t.schoolLocalId.equals(schoolLocalId) &
              t.isCurrent.equals(true))
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  /// Get a term by ID.
  Future<Term?> getById(int id) async {
    final results =
        await (select(terms)..where((t) => t.id.equals(id))..limit(1)).get();
    return results.isEmpty ? null : results.first;
  }

  /// Set a specific term as current (unsets all others for the school first).
  Future<void> setCurrent(int termId, int schoolLocalId) async {
    // Unset all current flags for this school
    await (update(terms)
          ..where((t) => t.schoolLocalId.equals(schoolLocalId)))
        .write(const TermsCompanion(isCurrent: Value(false)));

    // Set the target term as current
    await (update(terms)..where((t) => t.id.equals(termId)))
        .write(const TermsCompanion(isCurrent: Value(true)));
  }

  /// Update a term.
  Future<void> updateConfig(int id, TermsCompanion companion) async {
    await (update(terms)..where((t) => t.id.equals(id))).write(companion);
  }

  /// Delete a term by ID.
  Future<void> deleteById(int id) async {
    await (delete(terms)..where((t) => t.id.equals(id))).go();
  }

  /// Get the term for a given date.
  Future<Term?> getTermForDate(
      int schoolLocalId, DateTime date) async {
    final dateExpr = Variable<DateTime>(date);
    final results = await (select(terms)
          ..where((t) =>
              t.schoolLocalId.equals(schoolLocalId) &
              t.startDate.isSmallerOrEqual(dateExpr) &
              t.endDate.isSmallerThan(dateExpr).not())
          ..limit(1))
        .get();
    return results.isEmpty ? null : results.first;
  }

  /// Calculate the week number within a term for a given date.
  /// Returns 0 if the date is outside any term.
  Future<int> getWeekNumberForDate(
      int schoolLocalId, DateTime date) async {
    final term = await getTermForDate(schoolLocalId, date);
    if (term == null) return 0;
    final diff = date.difference(term.startDate);
    return (diff.inDays ~/ 7) + 1;
  }
}
