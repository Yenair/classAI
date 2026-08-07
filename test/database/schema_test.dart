import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  test('all tables created', () async {
    final tables = await db
        .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
        .get();
    final names = tables.map((r) => r.read<String>('name')).toList();
    expect(names, contains('schools'));
    expect(names, contains('teachers'));
    expect(names, contains('lessons'));
    expect(names, contains('version_hashes'));
    expect(names, contains('conflicts'));
    expect(names, contains('field_conflict_history'));
    expect(names, contains('security_config'));
    // ... all other tables
  });

  test('integrity check passes', () async {
    final result = await db.customSelect('PRAGMA integrity_check').get();
    expect(result.first.read<String>('integrity_check'), 'ok');
  });

  // test('WAL mode enabled', () async {
  // final result = await db.customSelect('PRAGMA journal_mode').get();
  //expect(result.first.read<String>('journal_mode'), 'wal');
  //});
}
