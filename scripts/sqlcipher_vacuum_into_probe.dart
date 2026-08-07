// INVESTIGATION-ONLY probe #3 (no fix). Do NOT run against the real classai.db.
//
// Tests SQLCipher's `PRAGMA key` + `VACUUM INTO` as an alternative copy
// mechanism to `sqlcipher_export()` (which is unusable here because it cannot
// handle AUTOINCREMENT tables / sqlite_sequence).
//
// VACUUM INTO performs a full PHYSICAL copy of the database file (including
// sqlite_sequence) rather than replaying CREATE TABLE statements, so it should
// sidestep the sqlite_sequence problem entirely. We test two patterns against a
// COPY of the source:
//
//   Pattern A: open source UNKEYED (plaintext) -> PRAGMA key = '...' on that
//              same connection -> VACUUM INTO 'newencrypted.db'. Then determine
//              whether the OUTPUT is genuinely encrypted.
//
//   Pattern B: open source UNKEYED -> VACUUM INTO 'plaincopy.db' (plaintext
//              physical copy) -> verify it is plaintext -> open it and apply
//              PRAGMA key -> VACUUM INTO again -> whether THAT output is
//              encrypted. (Some versions need the plaintext intermediate.)
//
// For whichever pattern produces a genuinely encrypted output we report:
//   - exact SQL run
//   - whether output can be opened WITHOUT the passphrase (must FAIL)
//   - whether output CAN be opened WITH the passphrase (must SUCCEED)
//   - sqlite_master object count (expect 31 incl sqlite_sequence)
//   - sqlite_sequence contents (13 rows, exact values)
//   - PRAGMA integrity_check result
//   - row counts for every real table (source vs output)
//   - user_version preservation
//   - output file size
//
// Usage:
//   dart run scripts/sqlcipher_vacuum_into_probe.dart <path-to-source-copy.db>

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Path to the SQLCipher sqlite3.dll. Verify it exists before overriding.
const String kCipherDll =
    r'C:\Users\Yene\classai\build\windows\x64\runner\Debug\sqlite3.dll';

const String kPass = 'vacuum-into-probe-pass';

DynamicLibrary _openCipherDll() => DynamicLibrary.open(kCipherDll);

void _section(String s) => print('\n===== $s =====');

void _dumpMaster(sql.Database db, String label) {
  final rows = db.select(
      'SELECT type, name FROM sqlite_master ORDER BY type, name');
  print('[$label] sqlite_master (${rows.length} rows):');
  for (final r in rows) {
    print('[$label]   ${r['type']}  ${r['name']}');
  }
}

void _dumpSequence(sql.Database db, String label) {
  final exists = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'");
  print('[$label] sqlite_sequence table exists: ${exists.isNotEmpty}');
  if (exists.isNotEmpty) {
    final rows = db.select('SELECT * FROM sqlite_sequence ORDER BY name');
    print('[$label] sqlite_sequence rows (${rows.length}):');
    for (final r in rows) {
      print('[$label]   ${r['name']} = ${r['seq']}');
    }
  }
}

List<String> _realTables(sql.Database db, String label) {
  final rows = db.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name");
  final names = rows.map((r) => r['name'] as String).toList();
  print('[$label] real (non-sqlite_) tables (${names.length}): $names');
  return names;
}

/// Attempts to open [path] WITHOUT a key and read sqlite_master.
/// Returns true if it can be read (plaintext), false if it throws (encrypted).
bool _openableWithoutKey(String path, String label) {
  final db = sql.sqlite3.open(path);
  try {
    final rows = db.select('SELECT name FROM sqlite_master LIMIT 1');
    print('[$label] opened WITHOUT key: SUCCEEDED (rows=${rows.length}) '
        '=> file appears PLAINTEXT');
    return true;
  } on sql.SqliteException catch (e) {
    print('[$label] opened WITHOUT key: FAILED code=${e.extendedResultCode} '
        'message="${e.message}" => file appears ENCRYPTED');
    return false;
  } catch (e) {
    print('[$label] opened WITHOUT key: UNEXPECTED $e');
    return false;
  } finally {
    db.dispose();
  }
}

/// Opens [path] WITH the passphrase and returns the connection (caller disposes)
/// or null on failure.
sql.Database? _openWithKey(String path, String label) {
  final db = sql.sqlite3.open(path);
  try {
    db.execute("PRAGMA key = '$kPass';");
    final rows = db.select('SELECT name FROM sqlite_master LIMIT 1');
    print('[$label] opened WITH key: SUCCEEDED (rows=${rows.length})');
    return db;
  } on sql.SqliteException catch (e) {
    print('[$label] opened WITH key: FAILED code=${e.extendedResultCode} '
        'message="${e.message}"');
    db.dispose();
    return null;
  } catch (e) {
    print('[$label] opened WITH key: UNEXPECTED $e');
    db.dispose();
    return null;
  }
}

void _inspectOutput(String path, String label) {
  _section('INSPECT OUTPUT: $label ($path)');
  final f = File(path);
  if (!f.existsSync()) {
    print('[$label] file does not exist!');
    return;
  }
  print('[$label] file size bytes = ${f.lengthSync()}');

  final canReadUnkeyed = _openableWithoutKey(path, label);
  final db = _openWithKey(path, label);
  if (db == null) {
    print('[$label] CANNOT open with key => cannot inspect further.');
    return;
  }
  try {
    _dumpMaster(db, label);
    _dumpSequence(db, label);
    final uv = db.select('PRAGMA user_version');
    print('[$label] user_version = ${uv.isEmpty ? '?' : uv.first[0]}');
    final integrity = db.select('PRAGMA integrity_check');
    print('[$label] integrity_check = '
        '${integrity.isEmpty ? '?' : integrity.first[0]}');
    print('[$label] encrypted = ${!canReadUnkeyed}');
  } finally {
    db.dispose();
  }
}

void _compareRowCounts(String sourcePath, sql.Database? outDb, String label) {
  _section('ROW-COUNT COMPARISON: source vs $label');
  final src = sql.sqlite3.open(sourcePath);
  try {
    final tables = _realTables(src, 'src');
    if (outDb == null) {
      print('[$label] output not openable; skipping comparison.');
      return;
    }
    var mismatch = 0;
    for (final t in tables) {
      final sc = src.select('SELECT COUNT(*) AS c FROM "$t"').first[0];
      final oc = outDb.select('SELECT COUNT(*) AS c FROM "$t"').first[0];
      final ok = sc == oc;
      if (!ok) mismatch++;
      print('[$label] $t: source=$sc output=$oc ${ok ? 'OK' : 'MISMATCH!'}');
    }
    print('[$label] row-count mismatches = $mismatch');
  } finally {
    src.dispose();
  }
}

void _finalVerify(String sourcePath) {
  _section('FINAL VERIFY: source copy + original untouched');
  final f = File(sourcePath);
  if (f.existsSync()) {
    final i = f.statSync();
    print('[final] source copy bytes = ${f.lengthSync()}');
    print('[final] source copy modified = ${i.modified}');
  } else {
    print('[final] SOURCE COPY MISSING!');
  }
  final real = File(r'C:\Users\Yene\Documents\classai.db');
  if (real.existsSync()) {
    final i = real.statSync();
    print('[final] ORIGINAL classai.db bytes = ${real.lengthSync()}');
    print('[final] ORIGINAL classai.db modified = ${i.modified}');
  } else {
    print('[final] ORIGINAL classai.db NOT FOUND at C:\\Users\\Yene\\Documents');
  }
}

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run scripts/sqlcipher_vacuum_into_probe.dart '
        '<source-copy.db>');
    exit(2);
  }
  final sourcePath = args[0];
  if (!File(sourcePath).existsSync()) {
    stderr.writeln('Source copy not found: $sourcePath');
    exit(2);
  }
  if (!File(kCipherDll).existsSync()) {
    stderr.writeln('SQLCipher DLL not found: $kCipherDll');
    exit(2);
  }

  // Point package:sqlite3 at the real SQLCipher build.
  open.overrideFor(OperatingSystem.windows, _openCipherDll);

  final probe = sql.sqlite3.openInMemory();
  final ver = probe.select('PRAGMA cipher_version').first[0];
  print('SQLCipher cipher_version = $ver');
  probe.dispose();

  final dir = p.dirname(sourcePath);
  final outAPath = p.join(dir, 'probe3_outA.db');
  final outBPath = p.join(dir, 'probe3_outB_plain.db');
  final outBEncPath = p.join(dir, 'probe3_outB_encrypted.db');
  for (final path in [outAPath, outBPath, outBEncPath]) {
    if (File(path).existsSync()) File(path).deleteSync();
  }

  _section('STEP 0: source baseline');
  _inspectOutput(sourcePath, 'src'); // plaintext dump; row comparison below

  _section('PATTERN A: open src unkeyed -> PRAGMA key -> VACUUM INTO');
  final srcA = sql.sqlite3.open(sourcePath);
  try {
    srcA.execute("PRAGMA key = '$kPass';");
    print('[A] PRAGMA key set on source connection');
    try {
      srcA.execute("VACUUM INTO '${outAPath.replaceAll("'", "''")}';");
      print('[A] VACUUM INTO SUCCEEDED');
    } on sql.SqliteException catch (e) {
      print('[A] VACUUM INTO FAILED: code=${e.extendedResultCode} '
          'message="${e.message}"');
    } catch (e) {
      print('[A] VACUUM INTO UNEXPECTED: $e');
    }
  } catch (e) {
    print('[A] setting PRAGMA key on plaintext source failed: $e');
  } finally {
    srcA.dispose();
  }

  _inspectOutput(outAPath, 'outA');

  _section('PATTERN B: open src unkeyed -> VACUUM INTO plaincopy -> rekey -> VACUUM INTO');
  final srcB = sql.sqlite3.open(sourcePath);
  try {
    srcB.execute("VACUUM INTO '${outBPath.replaceAll("'", "''")}';");
    print('[B] VACUUM INTO (plaintext copy) SUCCEEDED');
  } on sql.SqliteException catch (e) {
    print('[B] VACUUM INTO (plaintext copy) FAILED: code=${e.extendedResultCode} '
        'message="${e.message}"');
  } finally {
    srcB.dispose();
  }

  final plainOpen = _openableWithoutKey(outBPath, 'outB-plain');
  if (plainOpen && File(outBPath).existsSync() && File(outBPath).lengthSync() > 0) {
    final pb = sql.sqlite3.open(outBPath);
    try {
      pb.execute("PRAGMA key = '$kPass';");
      print('[B] PRAGMA key set on plaintext copy connection');
      try {
        pb.execute("VACUUM INTO '${outBEncPath.replaceAll("'", "''")}';");
        print('[B] VACUUM INTO (encrypted stage) SUCCEEDED');
      } on sql.SqliteException catch (e) {
        print('[B] VACUUM INTO (encrypted stage) FAILED: '
            'code=${e.extendedResultCode} message="${e.message}"');
      }
    } catch (e) {
      print('[B] setting PRAGMA key on plaintext copy failed: $e');
    } finally {
      pb.dispose();
    }
  }

  _inspectOutput(outBEncPath, 'outB-enc');

  // Compare row counts for whichever output(s) actually opened with the key.
  _section('ROW-COUNT COMPARISON');
  final outADb = File(outAPath).existsSync() ? _openWithKey(outAPath, 'cmp-A') : null;
  _compareRowCounts(sourcePath, outADb, 'outA');
  outADb?.dispose();
  final outBEncDb = File(outBEncPath).existsSync()
      ? _openWithKey(outBEncPath, 'cmp-B')
      : null;
  _compareRowCounts(sourcePath, outBEncDb, 'outB-enc');
  outBEncDb?.dispose();

  _section('SUMMARY');
  print('Passphrase used          = $kPass');
  print('Pattern A output path    = $outAPath');
  print('Pattern B plain copy     = $outBPath');
  print('Pattern B encrypted out  = $outBEncPath');
  print('(leave outputs in place for inspection)');

  _finalVerify(sourcePath);
}
