// INVESTIGATION-ONLY probe. Do NOT run against the real classai.db.
//
// Prototype a manual plaintext -> encrypted copy path that does NOT use
// sqlcipher_export(). The script:
//   1. Creates a fresh disposable plaintext copy via VACUUM INTO.
//   2. Opens a new encrypted destination connection and sets PRAGMA key.
//   3. ATTACHes the plaintext copy as "plaintext".
//   4. Copies tables one by one using CREATE TABLE + INSERT INTO ... SELECT *.
//   5. Recreates indexes with sql != NULL one by one.
//   6. Inserts the known sqlite_sequence rows directly.
//   7. Detaches, sets user_version, and verifies encryption/integrity/row counts.
//   8. Confirms the real classai.db is untouched.
//
// Usage:
//   dart run scripts/sqlcipher_manual_copy_probe.dart \
//       "C:\Users\Yene\Documents\classai_sqlcipher_probe\classai.db" \
//       "C:\Users\Yene\Documents\classai.db"

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const String kCipherDll =
    r'C:\Users\Yene\classai\build\windows\x64\runner\Debug\sqlite3.dll';

const String kPass = 'probe-test-passphrase';
const int kExpectedRealTableCount = 28;

const Map<String, int> kExpectedSequences = {
  'conflicts': 144,
  'exams': 145,
  'lessons': 173,
  'payment_events': 20,
  'progress_logs': 1,
  'scheme_of_work': 123,
  'schools': 11,
  'security_config': 1,
  'subjects': 4,
  'sync_queue': 351,
  'teacher_subjects': 2,
  'teachers': 120,
  'version_hashes': 42400,
};

const Set<String> kFtsShadowTables = {
  'search_index_data',
  'search_index_idx',
  'search_index_content',
  'search_index_docsize',
  'search_index_config',
};

DynamicLibrary _openCipherDll() => DynamicLibrary.open(kCipherDll);

void _section(String s) => print('\n===== $s =====');

String _sqlLiteral(String value) => value.replaceAll("'", "''");

String _countValue(Map<String, Object?> row) {
  final value = row['c'];
  return '$value';
}

void _printFileStat(String label, String path) {
  final file = File(path);
  if (!file.existsSync()) {
    print('[$label] missing: $path');
    return;
  }
  final stat = file.statSync();
  print('[$label] path = $path');
  print('[$label] size bytes = ${file.lengthSync()}');
  print('[$label] modified = ${stat.modified}');
}

List<Map<String, Object?>> _queryRows(sql.Database db, String sqlText) {
  return db
      .select(sqlText)
      .map((row) => row.map((key, value) => MapEntry(key, value)))
      .toList();
}

String? _firstTokenFromText(String? text) {
  if (text == null) return null;
  final match = RegExp(r'[A-Za-z0-9_]+').firstMatch(text);
  if (match == null) return null;
  final token = match.group(0);
  if (token == null || token.trim().isEmpty) return null;
  return token;
}

void _execOrAbort(sql.Database db, String label, String sqlText) {
  print('[$label] SQL: $sqlText');
  try {
    db.execute(sqlText);
    print('[$label] SUCCESS');
  } on sql.SqliteException catch (e) {
    print('[$label] FAILED code=${e.extendedResultCode} message="${e.message}"');
    rethrow;
  }
}

sql.Database? _openWithKey(String path, String passphrase, String label) {
  final db = sql.sqlite3.open(path);
  try {
    db.execute("PRAGMA key = '$passphrase';");
    final rows = db.select('SELECT name FROM sqlite_master LIMIT 1');
    print('[$label] opened WITH key: SUCCEEDED (rows=${rows.length})');
    return db;
  } on sql.SqliteException catch (e) {
    print('[$label] opened WITH key: FAILED code=${e.extendedResultCode} '
        'message="${e.message}"');
    db.dispose();
    return null;
  }
}

bool _openWithoutKey(String path, String label) {
  final db = sql.sqlite3.open(path);
  try {
    final rows = db.select('SELECT name FROM sqlite_master LIMIT 1');
    print('[$label] opened WITHOUT key: SUCCEEDED (rows=${rows.length})');
    return true;
  } on sql.SqliteException catch (e) {
    print('[$label] opened WITHOUT key: FAILED code=${e.extendedResultCode} '
        'message="${e.message}"');
    return false;
  } finally {
    db.dispose();
  }
}

List<Map<String, Object?>> _realTables(sql.Database db) {
  final rows = _queryRows(
    db,
    "SELECT name, sql FROM plaintext.sqlite_master "
    "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
    'ORDER BY rowid',
  );
  print('[source] real table count = ${rows.length}');
  print('[source] real table names = ${rows.map((r) => r['name']).toList()}');
  return rows;
}

List<Map<String, Object?>> _indexes(sql.Database db) {
  final rows = _queryRows(
    db,
    "SELECT name, sql FROM plaintext.sqlite_master "
    "WHERE type='index' AND sql IS NOT NULL "
    'ORDER BY rowid',
  );
  print('[source] index count with sql != NULL = ${rows.length}');
  return rows;
}

bool _sourceAppearsPlaintext(String path) {
  final db = sql.sqlite3.open(path);
  try {
    db.select('SELECT name FROM sqlite_master LIMIT 1');
    return true;
  } on sql.SqliteException {
    return false;
  } finally {
    db.dispose();
  }
}

void _deleteIfExists(String path) {
  final file = File(path);
  if (file.existsSync()) {
    file.deleteSync();
  }
  for (final suffix in const ['-wal', '-shm']) {
    final sidecar = File(path + suffix);
    if (sidecar.existsSync()) {
      sidecar.deleteSync();
    }
  }
}

void _compareCounts(sql.Database dest, String originalPath, List<String> tables) {
  final original = sql.sqlite3.open(originalPath);
  try {
    for (final table in tables) {
      final srcCount = _countValue(
        original.select('SELECT COUNT(*) AS c FROM "$table"').first,
      );
      final dstCount = _countValue(
        dest.select('SELECT COUNT(*) AS c FROM "$table"').first,
      );
      final ok = srcCount == dstCount;
      print('[counts] $table: original=$srcCount destination=$dstCount '
          '${ok ? 'OK' : 'MISMATCH!'}');
      if (!ok) {
        throw StateError('Row-count mismatch for "$table": '
            'original=$srcCount destination=$dstCount');
      }
    }
  } finally {
    original.dispose();
  }
}

void _verifySequences(sql.Database db) {
  final rows = _queryRows(
    db,
    'SELECT name, seq FROM main.sqlite_sequence ORDER BY name',
  );
  print('[verify] sqlite_sequence rows (${rows.length}):');
  for (final row in rows) {
    print('[verify]   ${row['name']} = ${row['seq']}');
  }

  for (final entry in kExpectedSequences.entries) {
    final match = rows.where((row) => row['name'] == entry.key).toList();
    if (match.isEmpty) {
      throw StateError('Missing sqlite_sequence row for ${entry.key}');
    }
    final seq = match.first['seq'];
    final seqValue = seq is int ? seq : int.tryParse('$seq');
    if (seqValue != entry.value) {
      throw StateError('sqlite_sequence mismatch for ${entry.key}: '
          'expected=${entry.value} actual=$seq');
    }
  }
}

void _verifyDestinationEncryption(String path, String passphrase) {
  final unkeyed = _openWithoutKey(path, 'dest-reopen-unkeyed');
  print('[verify] destination opens WITHOUT key = $unkeyed');
  if (unkeyed) {
    throw StateError('Destination should be encrypted but opened without key.');
  }

  final keyed = _openWithKey(path, passphrase, 'dest-reopen-keyed');
  if (keyed == null) {
    throw StateError('Destination failed to reopen with the passphrase.');
  }
  try {
    final integrity = keyed.select('PRAGMA integrity_check');
    final result = integrity.isEmpty ? '?' : '${integrity.first[0]}';
    print('[verify] reopened integrity_check = $result');
    if (result != 'ok') {
      throw StateError('Integrity check failed on reopened destination: $result');
    }
  } finally {
    keyed.dispose();
  }
}

void _writeSequence(sql.Database db, String name, int seq) {
  final sqlText =
      "INSERT OR REPLACE INTO main.sqlite_sequence (name, seq) VALUES ('${_sqlLiteral(name)}', $seq);";
  print('[sequence:$name] SQL: $sqlText');
  try {
    db.execute(sqlText);
    print('[sequence:$name] SUCCESS');
  } on sql.SqliteException catch (e) {
    print('[sequence:$name] FAILED code=${e.extendedResultCode} '
        'message="${e.message}"');
    rethrow;
  }
}

String? _discoverFtsToken(sql.Database db) {
  final rows = _queryRows(
    db,
    'SELECT topic AS text_a, content AS text_b FROM plaintext.lessons '
    'UNION ALL '
    'SELECT topic AS text_a, content AS text_b FROM plaintext.exams '
    'UNION ALL '
    'SELECT title AS text_a, content AS text_b FROM plaintext.vault_items '
    'LIMIT 50',
  );
  for (final row in rows) {
    final textAToken = _firstTokenFromText(row['text_a'] as String?);
    if (textAToken != null) return textAToken;
    final textBToken = _firstTokenFromText(row['text_b'] as String?);
    if (textBToken != null) return textBToken;
  }
  return null;
}

void _compareFtsQuery(sql.Database original, sql.Database dest, String token) {
  final sqlText =
      "SELECT count(*) AS c FROM search_index WHERE search_index MATCH '${_sqlLiteral(token)}'";
  print('[fts] SQL: $sqlText');
  final originalCount = _countValue(original.select(sqlText).first);
  final destCount = _countValue(dest.select(sqlText).first);
  print('[fts] token = $token');
  print('[fts] original MATCH count = $originalCount');
  print('[fts] destination MATCH count = $destCount');
  if (originalCount != destCount) {
    throw StateError('FTS MATCH count mismatch for token "$token": '
        'original=$originalCount destination=$destCount');
  }
}

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run scripts/sqlcipher_manual_copy_probe.dart '
      '<disposable-source.db> <original.db>',
    );
    exit(2);
  }

  final sourcePath = args[0];
  final originalPath = args[1];
  if (!File(sourcePath).existsSync()) {
    stderr.writeln('Source copy not found: $sourcePath');
    exit(2);
  }
  if (!File(originalPath).existsSync()) {
    stderr.writeln('Original db not found: $originalPath');
    exit(2);
  }
  if (p.equals(p.normalize(sourcePath), p.normalize(originalPath))) {
    stderr.writeln('Source and original paths must be different.');
    exit(2);
  }
  if (!File(kCipherDll).existsSync()) {
    stderr.writeln('SQLCipher DLL not found: $kCipherDll');
    exit(2);
  }

  open.overrideFor(OperatingSystem.windows, _openCipherDll);

  final probe = sql.sqlite3.openInMemory();
  try {
    final ver = probe.select('PRAGMA cipher_version').first[0];
    print('SQLCipher cipher_version = $ver');
  } finally {
    probe.dispose();
  }

  if (!_sourceAppearsPlaintext(sourcePath)) {
    stderr.writeln('Source disposable copy is not readable as plaintext: $sourcePath');
    exit(1);
  }

  final sourceDir = p.dirname(sourcePath);
  final plainCopyPath = p.join(sourceDir, 'manual_copy_plaintext.db');
  final destPath = p.join(sourceDir, 'manual_copy_encrypted.db');
  _deleteIfExists(plainCopyPath);
  _deleteIfExists(destPath);

  _section('STEP 1: fresh VACUUM INTO plaintext copy');
  final source = sql.sqlite3.open(sourcePath);
  try {
    final vacuumSql = "VACUUM INTO '${_sqlLiteral(plainCopyPath)}';";
    print('[step1] SQL: $vacuumSql');
    source.execute(vacuumSql);
    print('[step1] VACUUM INTO SUCCESS');
  } on sql.SqliteException catch (e) {
    print('[step1] VACUUM INTO FAILED code=${e.extendedResultCode} '
        'message="${e.message}"');
    source.dispose();
    _printFileStat('final-source', sourcePath);
    _printFileStat('final-original', originalPath);
    exit(1);
  } finally {
    source.dispose();
  }

  _printFileStat('step1-source-copy', plainCopyPath);

  _section('STEP 2: open new encrypted destination and ATTACH plaintext');
  final dest = sql.sqlite3.open(destPath);
  var attached = false;
  var destClosed = false;
  try {
    dest.execute("PRAGMA key = '$kPass';");
    print('[step2] PRAGMA key set');
    final attachSql =
        "ATTACH DATABASE '${_sqlLiteral(plainCopyPath)}' AS plaintext KEY '';";
    print('[step2] SQL: $attachSql');
    dest.execute(attachSql);
    attached = true;
    print('[step2] ATTACH SUCCESS');

    final tableRows = _realTables(dest);
    if (tableRows.length != kExpectedRealTableCount) {
      throw StateError('Expected $kExpectedRealTableCount real tables, '
          'found ${tableRows.length}');
    }

    _section('STEP 3: copy tables one by one');
    for (final row in tableRows) {
      final tableName = row['name'] as String;
      if (kFtsShadowTables.contains(tableName)) {
        print('[table:$tableName] SKIP shadow table auto-generated by FTS5');
        continue;
      }
      final tableSql = row['sql'] as String?;
      if (tableSql == null) {
        throw StateError('CREATE TABLE SQL unexpectedly null for $tableName');
      }
      if (tableName == 'search_index') {
        print('[table:search_index] CREATE VIRTUAL TABLE sql=');
        print(tableSql);
      }
      _execOrAbort(dest, 'table:$tableName:create', tableSql);
      final insertSql =
          'INSERT INTO main."$tableName" SELECT * FROM plaintext."$tableName";';
      _execOrAbort(dest, 'table:$tableName:insert', insertSql);
    }

    _section('STEP 4: recreate indexes');
    final indexRows = _indexes(dest);
    for (final row in indexRows) {
      final indexName = row['name'] as String;
      final indexSql = row['sql'] as String?;
      if (indexSql == null) {
        throw StateError('Index SQL unexpectedly null for $indexName');
      }
      _execOrAbort(dest, 'index:$indexName', indexSql);
    }

    _section('STEP 5: sqlite_sequence direct inserts');
    final seqExists = dest.select(
      "SELECT name FROM main.sqlite_master WHERE type='table' AND name='sqlite_sequence'",
    );
    print('[sequence] main.sqlite_sequence exists = ${seqExists.isNotEmpty}');
    if (seqExists.isEmpty) {
      throw StateError('main.sqlite_sequence does not exist after table copy.');
    }
    final preSeqRows = _queryRows(
      dest,
      'SELECT name, seq FROM main.sqlite_sequence ORDER BY name',
    );
    print('[sequence] pre-existing rows (${preSeqRows.length}):');
    for (final row in preSeqRows) {
      print('[sequence]   ${row['name']} = ${row['seq']}');
    }
    for (final entry in kExpectedSequences.entries) {
      // Keep the sequence list exact: wipe first, then repopulate with the
      // confirmed source values only.
      if (entry.key == kExpectedSequences.keys.first) {
        print('[sequence] SQL: DELETE FROM main.sqlite_sequence;');
        dest.execute('DELETE FROM main.sqlite_sequence;');
        print('[sequence] DELETE FROM main.sqlite_sequence SUCCESS');
      }
      _writeSequence(dest, entry.key, entry.value);
    }

    final ftsToken = _discoverFtsToken(dest);
    if (ftsToken == null) {
      throw StateError('Could not discover an FTS token from plaintext.search_index');
    }

    _section('STEP 6: detach and set user_version');
    dest.execute('DETACH DATABASE plaintext;');
    attached = false;
    print('[step6] DETACH SUCCESS');
    dest.execute('PRAGMA user_version = 21;');
    print('[step6] PRAGMA user_version = 21 SUCCESS');

    _section('STEP 7: verify destination while keyed');
    final integrity = dest.select('PRAGMA integrity_check');
    final integrityResult = integrity.isEmpty ? '?' : '${integrity.first[0]}';
    print('[verify] integrity_check = $integrityResult');
    if (integrityResult != 'ok') {
      throw StateError('Destination integrity_check failed: $integrityResult');
    }
    final uv = dest.select('PRAGMA user_version');
    final uvValue = uv.isEmpty ? '?' : '${uv.first[0]}';
    print('[verify] user_version = $uvValue');
    if (uvValue != '21') {
      throw StateError('Destination user_version mismatch: $uvValue');
    }

    final verifyTables = _queryRows(
      dest,
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY rowid",
    ).map((row) => row['name'] as String).toList();
    _compareCounts(dest, originalPath, verifyTables);
    _verifySequences(dest);
    final originalForFts = sql.sqlite3.open(originalPath);
    try {
      _compareFtsQuery(originalForFts, dest, ftsToken);
      final originalCount = _countValue(
        originalForFts.select('SELECT count(*) AS c FROM search_index').first,
      );
      final destinationCount = _countValue(
        dest.select('SELECT count(*) AS c FROM search_index').first,
      );
      print('[fts] SELECT count(*) FROM search_index original = $originalCount');
      print('[fts] SELECT count(*) FROM search_index destination = $destinationCount');
      if (originalCount != destinationCount) {
        throw StateError('search_index row-count mismatch: '
            'original=$originalCount destination=$destinationCount');
      }
    } finally {
      originalForFts.dispose();
    }

    _section('STEP 8: reopen destination and confirm encryption');
    dest.dispose();
    destClosed = true;

    _verifyDestinationEncryption(destPath, kPass);

    _section('STEP 9: file sizes and original untouched');
    _printFileStat('destination', destPath);
    _printFileStat('original', originalPath);

    print('\nRESULT: manual copy path completed successfully.');
    print('[result] sourcePath = $sourcePath');
    print('[result] plainCopyPath = $plainCopyPath');
    print('[result] destPath = $destPath');
    print('[result] originalPath = $originalPath');
  } on sql.SqliteException {
    rethrow;
  } on StateError catch (e) {
    print('[abort] $e');
    if (attached) {
      try {
        dest.execute('DETACH DATABASE plaintext;');
        print('[abort] DETACH SUCCESS during cleanup');
      } catch (err) {
        print('[abort] DETACH cleanup failed: $err');
      }
    }
    dest.dispose();
    destClosed = true;
    _printFileStat('final-source', sourcePath);
    _printFileStat('final-original', originalPath);
    exit(1);
  } on Object catch (e) {
    print('[abort] UNEXPECTED ERROR: $e');
    if (attached) {
      try {
        dest.execute('DETACH DATABASE plaintext;');
        print('[abort] DETACH SUCCESS during cleanup');
      } catch (err) {
        print('[abort] DETACH cleanup failed: $err');
      }
    }
    dest.dispose();
    destClosed = true;
    _printFileStat('final-source', sourcePath);
    _printFileStat('final-original', originalPath);
    exit(1);
  } finally {
    if (!destClosed) {
      dest.dispose();
    }
    _printFileStat('final-source', sourcePath);
    _printFileStat('final-original', originalPath);
  }
}
