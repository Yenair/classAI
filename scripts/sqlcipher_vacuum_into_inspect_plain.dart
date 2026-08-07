// INVESTIGATION-ONLY helper: inspect a PLAINTEXT database copy (no key) and
// report what VACUUM INTO preserved: sqlite_master count, sqlite_sequence rows,
// integrity, user_version, and row counts for the recorded real tables.
//
// Usage:
//   dart run scripts/sqlcipher_vacuum_into_inspect_plain.dart <plaintext.db>

import 'dart:ffi';
import 'dart:io';

import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const String kCipherDll =
    r'C:\Users\Yene\classai\build\windows\x64\runner\Debug\sqlite3.dll';

DynamicLibrary _openCipherDll() => DynamicLibrary.open(kCipherDll);

void _section(String s) => print('\n===== $s =====');

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln(
        'Usage: dart run scripts/sqlcipher_vacuum_into_inspect_plain.dart <plaintext.db>');
    exit(2);
  }
  final path = args[0];
  if (!File(path).existsSync()) {
    stderr.writeln('File not found: $path');
    exit(2);
  }
  if (!File(kCipherDll).existsSync()) {
    stderr.writeln('SQLCipher DLL not found: $kCipherDll');
    exit(2);
  }
  open.overrideFor(OperatingSystem.windows, _openCipherDll);

  final probe = sql.sqlite3.openInMemory();
  print('SQLCipher cipher_version = ${probe.select('PRAGMA cipher_version').first[0]}');
  probe.dispose();

  _section('INSPECT PLAINTEXT COPY: $path');
  final f = File(path);
  print('file size bytes = ${f.lengthSync()}');

  final db = sql.sqlite3.open(path);
  try {
    // Try to read unkeyed. Should succeed (plaintext).
    try {
      final rows = db.select('SELECT name FROM sqlite_master LIMIT 1');
      print('opened WITHOUT key: SUCCEEDED (rows=${rows.length})');
    } on sql.SqliteException catch (e) {
      print('opened WITHOUT key: FAILED code=${e.extendedResultCode} '
          'message="${e.message}"');
    }

    final master = db.select('SELECT type, name FROM sqlite_master ORDER BY type, name');
    print('sqlite_master (${master.length} rows):');
    for (final r in master) {
      print('  ${r['type']}  ${r['name']}');
    }

    final seqExists = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'");
    print('sqlite_sequence table exists: ${seqExists.isNotEmpty}');
    if (seqExists.isNotEmpty) {
      final rows = db.select('SELECT * FROM sqlite_sequence ORDER BY name');
      print('sqlite_sequence rows (${rows.length}):');
      for (final r in rows) {
        print('  ${r['name']} = ${r['seq']}');
      }
    }

    final uv = db.select('PRAGMA user_version');
    print('user_version = ${uv.isEmpty ? '?' : uv.first[0]}');

    final integrity = db.select('PRAGMA integrity_check');
    print('integrity_check = ${integrity.isEmpty ? '?' : integrity.first[0]}');

    final tables = db.select(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
    print('real (non-sqlite_) tables (${tables.length}):');
    for (final t in tables) {
      final c = db.select('SELECT COUNT(*) AS c FROM "${t['name']}"').first[0];
      print('  ${t['name']} = $c rows');
    }

    final searchCount = db.select('SELECT COUNT(*) AS c FROM search_index').first[0];
    print('search_index row count = $searchCount');
    final searchRows = db.select('SELECT * FROM search_index LIMIT 5');
    print('search_index sample rows (${searchRows.length}):');
    for (final r in searchRows) {
      print('  rowid=${r['rowid']} content_type=${r['content_type']} '
          'record_local_id=${r['record_local_id']} title=${r['title']} '
          'body=${r['body']}');
    }
  } finally {
    db.dispose();
  }
}
