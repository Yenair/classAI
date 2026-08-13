// test/sync/sow_term_migration_test.dart
//
// Regression test for the v27 local migration: scheme_of_work term values are
// normalised to the lowercase values ('first'/'second'/'third') that the
// server CHECK constraint (`scheme_of_work_term_check`) accepts. The client
// historically stored title-case terms ('First'), which the server rejects
// and the case-sensitive merge comparison assumes to be lowercase.
//
// The test seeds rows with the pre-migration values, runs the migration SQL
// exactly as written in lib/core/database/database.dart, and verifies both
// the normalisation and that no rows are lost.
import 'package:classai/core/database/database.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';

/// The v27 migration statement, kept in sync with the SQL in
/// lib/core/database/database.dart (`if (from < 27)` block) so the test
/// guards the exact UPDATE that runs on-device.
const String _v27TermMigrationSql = '''
  UPDATE scheme_of_work
  SET term = CASE
    WHEN LOWER(TRIM(term)) IN ('first', '1st', '1st term') THEN 'first'
    WHEN LOWER(TRIM(term)) IN ('second', '2nd', '2nd term') THEN 'second'
    WHEN LOWER(TRIM(term)) IN ('third', '3rd', '3rd term') THEN 'third'
    ELSE LOWER(TRIM(term))
  END
''';

/// Inserts a scheme_of_work row carrying the given pre-migration [term].
Future<int> _seedSowRow(AppDatabase db, String term) {
  return db.into(db.schemeOfWork).insert(
        SchemeOfWorkCompanion.insert(
          term: Value(term),
          weekNumber: const Value(1),
          topic: const Value('Topic'),
          objectives: const Value('Objectives'),
          status: const Value('draft'),
          classLevel: const Value('JSS 1'),
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
    await db.initialize();
  });

  tearDown(() async {
    await db.close();
  });

  test('v27 migration normalises scheme_of_work terms and keeps every row',
      () async {
    const seededTerms = [
      'First',
      'Second',
      'Third',
      '1st',
      '2nd Term',
      '3rd',
      'first',
    ];
    for (final term in seededTerms) {
      await _seedSowRow(db, term);
    }

    final before = await (db.select(db.schemeOfWork)).get();
    expect(before, hasLength(seededTerms.length));

    // Run the migration SQL exactly as written.
    await db.customStatement(_v27TermMigrationSql);

    // Row count unchanged — no data loss.
    final after = await (db.select(db.schemeOfWork)).get();
    expect(after, hasLength(seededTerms.length),
        reason: 'row count must be unchanged — no data loss');

    // Rows are seeded in order, so autoincrement ids map 1:1 to seededTerms.
    final termsById = {for (final r in after) r.id: r.term};
    expect(termsById[1], 'first'); // 'First'
    expect(termsById[2], 'second'); // 'Second'
    expect(termsById[3], 'third'); // 'Third'
    expect(termsById[4], 'first'); // '1st'
    expect(termsById[5], 'second'); // '2nd Term'
    expect(termsById[6], 'third'); // '3rd'
    expect(termsById[7], 'first'); // 'first'

    // Non-term fields survive untouched.
    expect(after.map((r) => r.topic).toSet(), {'Topic'});
    expect(after.map((r) => r.weekNumber).toSet(), {1});
  });

  test('v27 migration is idempotent', () async {
    await _seedSowRow(db, 'First');
    await _seedSowRow(db, 'second');
    await _seedSowRow(db, '3rd Term');

    await db.customStatement(_v27TermMigrationSql);
    await db.customStatement(_v27TermMigrationSql);

    final rows = await (db.select(db.schemeOfWork)).get();
    expect(rows, hasLength(3));
    expect(rows.map((r) => r.term).toSet(), {'first', 'second', 'third'});
  });

  test('unknown terms fall back to LOWER(TRIM(term))', () async {
    await _seedSowRow(db, '  Holiday  ');
    await _seedSowRow(db, '');

    await db.customStatement(_v27TermMigrationSql);

    final rows = await (db.select(db.schemeOfWork)).get();
    expect(rows, hasLength(2));
    expect(rows[0].term, 'holiday');
    expect(rows[1].term, '');
  });
}
