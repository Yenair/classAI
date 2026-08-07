// INVESTIGATION-ONLY probe #4 (no fix). Do NOT run against the real classai.db.
//
// Tests whether we can DELETE the ROWS from sqlite_sequence (not rename or
// drop the table) on a disposable VACUUM INTO plaintext copy, and whether that
// lets sqlcipher_export() succeed afterward (the export currently fails the
// moment it touches sqlite_sequence in the destination).
//
// Steps:
//   1. Fresh VACUUM INTO plaintext copy of the disposable source copy.
//   2. DELETE FROM sqlite_sequence; report exact result.
//   3. Check whether sqlite_sequence still exists in sqlite_master (just
//      empty) or is gone.
//   4. ATTACH + sqlcipher_export using THIS emptied copy as the plaintext
//      source.
//   5. Report export result. If SUCCESS: check destination sqlite_master
//      (31 objects expected), auto-created empty sqlite_sequence,
//      integrity_check, and row counts vs the ORIGINAL classai.db.
//   6. If export succeeded: manually INSERT the real sequence values into the
//      destination's sqlite_sequence and confirm they land correctly.
//   7. Confirm real classai.db untouched (size/timestamp).
//
// Usage:
//   dart run scripts/sqlcipher_delete_sequence_export_probe.dart \
//       <path-to-source-copy.db> <path-to-original.db>
//
//   Example:
//   dart run scripts/sqlcipher_delete_sequence_export_probe.dart \
//       "C:\Users\Yene\Documents\classai_sqlcipher_probe\classai.db" \
//       "C:\Users\Yene\Documents\classai.db"

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Path to the SQLCipher sqlite3.dll. Verify it exists before overriding.
const String kCipherDll =
    r'C:\Users\Yene\classai\build\windows\x64\runner\Debug\sqlite3.dll';

const String kPass = 'probe-test-passphrase';

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

/// Opens [path] WITHOUT a key and reads sqlite_master.
/// Returns true if readable (plaintext), false if it throws (encrypted).
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

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Usage: dart run scripts/sqlcipher_delete_sequence_export_probe.dart '
        '<source-copy.db> <original.db>');
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
  if (!File(kCipherDll).existsSync()) {
    stderr.writeln('SQLCipher DLL not found: $kCipherDll');
    exit(2);
  }

  open.overrideFor(OperatingSystem.windows, _openCipherDll);

  final probe = sql.sqlite3.openInMemory();
  final ver = probe.select('PRAGMA cipher_version').first[0];
  print('SQLCipher cipher_version = $ver');
  probe.dispose();

  final dir = p.dirname(sourcePath);
  final plainCopy = p.join(dir, 'probe4_plain.db');
  final encOut = p.join(dir, 'probe4_out_encrypted.db');
  for (final path in [plainCopy, encOut]) {
    if (File(path).existsSync()) File(path).deleteSync();
  }

  _section('STEP 1: fresh VACUUM INTO plaintext copy of the disposable source');
  final src = sql.sqlite3.open(sourcePath);
  try {
    src.execute("VACUUM INTO '${plainCopy.replaceAll("'", "''")}';");
    print('[step1] VACUUM INTO (plaintext copy) SUCCEEDED');
  } on sql.SqliteException catch (e) {
    print('[step1] VACUUM INTO FAILED: code=${e.extendedResultCode} '
        'message="${e.message}"');
    print('[step1] ABORTING probe (cannot make disposable copy).');
    src.dispose();
    _finalVerify(originalPath);
    exit(1);
  } finally {
    src.dispose();
  }
  print('[step1] plaintext copy bytes = ${File(plainCopy).lengthSync()}');
  _dumpMaster(sql.sqlite3.open(plainCopy), 'plain-before');
  _dumpSequence(sql.sqlite3.open(plainCopy), 'plain-before');
  final plainC = sql.sqlite3.open(plainCopy);
  plainC.dispose();

  _section('STEP 2: DELETE FROM sqlite_sequence on the disposable copy');
  final d = sql.sqlite3.open(plainCopy);
  try {
    d.execute('DELETE FROM sqlite_sequence;');
    print('[step2] DELETE FROM sqlite_sequence SUCCEEDED (no exception)');
  } on sql.SqliteException catch (e) {
    print('[step2] DELETE FROM sqlite_sequence FAILED: code=${e.extendedResultCode} '
        'message="${e.message}"');
    print('[step2] ABORTING probe (as instructed on step 2 failure).');
    d.dispose();
    _finalVerify(originalPath);
    exit(1);
  } catch (e) {
    print('[step2] DELETE FROM sqlite_sequence UNEXPECTED: $e');
    d.dispose();
    _finalVerify(originalPath);
    exit(1);
  }

  _section('STEP 3: check sqlite_sequence existence after DELETE');
  final stillExists = d.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'");
  print('[step3] sqlite_sequence table exists after DELETE: ${stillExists.isNotEmpty}');
  if (stillExists.isNotEmpty) {
    final rows = d.select('SELECT * FROM sqlite_sequence ORDER BY name');
    print('[step3] sqlite_sequence rows after DELETE (${rows.length}):');
    for (final r in rows) {
      print('[step3]   ${r['name']} = ${r['seq']}');
    }
  }
  d.dispose();

  _section('STEP 4: ATTACH + sqlcipher_export against the EMPTIED copy');
  final out = sql.sqlite3.open(encOut);
  var exportSucceeded = false;
  try {
    out.execute("PRAGMA key = '$kPass';");
    out.execute(
        "ATTACH DATABASE '${plainCopy.replaceAll("'", "''")}' AS plaintext KEY '';");
    print('[step4] ATTACH ok');

    final attachedSeq = out.select(
        "SELECT name FROM plaintext.sqlite_master WHERE type='table' AND name='sqlite_sequence'");
    print('[step4] plaintext.sqlite_sequence exists: ${attachedSeq.isNotEmpty}');

    out.execute("SELECT sqlcipher_export('plaintext');");
    print('[step4] sqlcipher_export SUCCEEDED');
    exportSucceeded = true;
  } on sql.SqliteException catch (e) {
    print('[step4] FAILED: code=${e.extendedResultCode} '
        'message="${e.message}"');
    exportSucceeded = false;
  } catch (e) {
    print('[step4] UNEXPECTED ERROR: $e');
    exportSucceeded = false;
  }

  try {
    out.execute('DETACH DATABASE plaintext;');
    print('[step4] DETACH ok');
  } catch (e) {
    print('[step4] DETACH failed (expected if export rolled back): $e');
  }

  _section('STEP 5: result');
  print('[step5] exportSucceeded = $exportSucceeded');
  final encExists = File(encOut).existsSync();
  print('[step5] encrypted file exists: $encExists');
  if (encExists) {
    print('[step5] encrypted file bytes: ${File(encOut).lengthSync()}');
  }

  if (!exportSucceeded) {
    print('[step5] Export FAILED. Per instructions, STOP HERE. '
        'Original untouched check below.');
    out.dispose();
    _finalVerify(originalPath);
    exit(0);
  }

  // Inspect destination.
  final dest = _openWithKey(encOut, 'out');
  if (dest != null) {
    try {
      _dumpMaster(dest, 'out');
      _dumpSequence(dest, 'out');
      final uv = dest.select('PRAGMA user_version');
      print('[out] user_version = ${uv.isEmpty ? '?' : uv.first[0]}');
      final integrity = dest.select('PRAGMA integrity_check');
      print('[out] integrity_check = '
          '${integrity.isEmpty ? '?' : integrity.first[0]}');
      final canReadUnkeyed = _openableWithoutKey(encOut, 'out-unkeyed');
      print('[out] encrypted = ${!canReadUnkeyed}');
    } finally {
      dest.dispose();
    }
  }

  _section('STEP 5b: row counts destination vs ORIGINAL classai.db');
  final orig = sql.sqlite3.open(originalPath);
  final outD = _openWithKey(encOut, 'cmp');
  var mismatch = 0;
  try {
    final tables = _realTables(orig, 'orig');
    for (final t in tables) {
      final oc = orig.select('SELECT COUNT(*) AS c FROM "$t"').first[0];
      final dc = outD == null
          ? -1
          : outD.select('SELECT COUNT(*) AS c FROM "$t"').first[0];
      final ok = oc == dc;
      if (!ok) mismatch++;
      print('[cmp] $t: original=$oc destination=$dc ${ok ? 'OK' : 'MISMATCH!'}');
    }
    print('[cmp] row-count mismatches = $mismatch');
  } finally {
    orig.dispose();
    outD?.dispose();
  }

  _section('STEP 6: manually INSERT real sequence values into destination');
  final ins = _openWithKey(encOut, 'insert');
  if (ins == null) {
    print('[step6] cannot open destination with key; skipping INSERT test.');
  } else {
    try {
      final vals = {
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
      for (final e in vals.entries) {
        ins.execute(
            "INSERT OR REPLACE INTO sqlite_sequence (name, seq) "
            "VALUES ('${e.key}', ${e.value});");
      }
      print('[step6] all INSERT OR REPLACE statements SUCCEEDED');
      _dumpSequence(ins, 'inserted');
      final iv = ins.select('PRAGMA integrity_check');
      print('[step6] integrity_check after INSERT = '
          '${iv.isEmpty ? '?' : iv.first[0]}');
    } on sql.SqliteException catch (e) {
      print('[step6] INSERT FAILED: code=${e.extendedResultCode} '
          'message="${e.message}"');
    } catch (e) {
      print('[step6] INSERT UNEXPECTED: $e');
    } finally {
      ins.dispose();
    }
  }

  _section('SUMMARY');
  print('exportSucceeded = $exportSucceeded');
  print('source (disposable)      = $sourcePath');
  print('plaintext emptied copy    = $plainCopy');
  print('encrypted output path     = $encOut');
  print('(leave outputs in place for inspection)');

  _finalVerify(originalPath);
}

void _finalVerify(String originalPath) {
  _section('FINAL VERIFY: original classai.db untouched');
  final real = File(originalPath);
  if (real.existsSync()) {
    final i = real.statSync();
    print('[final] ORIGINAL classai.db bytes = ${real.lengthSync()}');
    print('[final] ORIGINAL classai.db modified = ${i.modified}');
  } else {
    print('[final] ORIGINAL classai.db NOT FOUND at $originalPath');
  }
}
