// INVESTIGATION-ONLY probe (no fix). Do NOT run against the real classai.db.
//
// Uses the real SQLCipher native library (the 8.9MB sqlite3.dll bundled by
// sqlcipher_flutter_libs under build/windows/x64) via package:sqlite3's
// open.overrideFor, then tests the "rename sqlite_sequence out of the way"
// idea against a COPY of the database.
//
// Usage:
//   dart run scripts/sqlcipher_export_probe.dart <path-to-source-copy.db>
//
// The probe:
//   1. Opens the source copy DIRECTLY (plaintext, unkeyed).
//   2. ALTER TABLE sqlite_sequence RENAME TO sqlite_sequence_backup;
//      (reports exact result or exact error)
//   3. Closes it, then runs the normal ATTACH + sqlcipher_export flow
//      against this modified copy into a fresh encrypted file.
//   4. Reports whether export succeeded or the exact new error.
//   5. Renames sqlite_sequence_backup back to sqlite_sequence and confirms.
//   6. Inspects the destination's auto-created sqlite_sequence and compares.
//   7. Reports everything verbatim.

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

// Path to the SQLCipher sqlite3.dll. Verify it exists before overriding.
const String kCipherDll =
    r'C:\Users\Yene\classai\build\windows\x64\runner\Debug\sqlite3.dll';

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

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run scripts/sqlcipher_export_probe.dart '
        '<source-copy.db>');
    exit(2);
  }
  final sourcePath = args[0];
  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('Source copy not found: $sourcePath');
    exit(2);
  }

  if (!File(kCipherDll).existsSync()) {
    stderr.writeln('SQLCipher DLL not found: $kCipherDll');
    exit(2);
  }

  // Point package:sqlite3 at the real SQLCipher build.
  open.overrideFor(OperatingSystem.windows, _openCipherDll);

  // Confirm the runtime really is SQLCipher.
  final probe = sql.sqlite3.openInMemory();
  final ver = probe.select('PRAGMA cipher_version').first[0];
  print('SQLCipher cipher_version = $ver');
  probe.dispose();

  final dir = p.dirname(sourcePath);
  final encPath = p.join(dir, 'probe_out_encrypted.db');
  // Clean any leftover from a prior run of this probe.
  if (File(encPath).existsSync()) File(encPath).deleteSync();

  _section('STEP 1: confirm source copy has sqlite_sequence');
  final src = sql.sqlite3.open(sourcePath);
  _dumpMaster(src, 'src');
  _dumpSequence(src, 'src');
  final srcUv = src.select('PRAGMA user_version');
  print('[src] user_version = ${srcUv.isEmpty ? '?' : srcUv.first[0]}');
  final srcSeqRows = src.select('SELECT * FROM sqlite_sequence ORDER BY name');
  print('[src] sqlite_sequence full dump (${srcSeqRows.length} rows):');
  for (final r in srcSeqRows) {
    print('[src]   ${r['name']} = ${r['seq']}');
  }
  src.dispose();

  _section('STEP 2a+2b: rename sqlite_sequence -> sqlite_sequence_backup');
  final r1 = sql.sqlite3.open(sourcePath);
  try {
    r1.execute(
        'ALTER TABLE sqlite_sequence RENAME TO sqlite_sequence_backup;');
    print('[rename] SUCCESS: sqlite_sequence renamed to sqlite_sequence_backup');
  } on sql.SqliteException catch (e) {
    print('[rename] FAILED: code=${e.extendedResultCode} '
        'message="${e.message}"');
    print('[rename] ABORTING probe (source copy left untouched by this step).');
    r1.dispose();
    _finalVerify(sourcePath);
    exit(1);
  } catch (e) {
    print('[rename] UNEXPECTED ERROR: $e');
    r1.dispose();
    _finalVerify(sourcePath);
    exit(1);
  }
  // Confirm the rename took effect.
  _dumpMaster(r1, 'renamed');
  final backupExists = r1.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence_backup'");
  print('[renamed] sqlite_sequence_backup exists: ${backupExists.isNotEmpty}');
  final seqGone = r1.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='sqlite_sequence'");
  print('[renamed] sqlite_sequence now exists: ${seqGone.isNotEmpty}');
  r1.dispose();

  _section('STEP 2c+2d: ATTACH + sqlcipher_export against the modified copy');
  final out = sql.sqlite3.open(encPath);
  var exportSucceeded = false;
  try {
    out.execute("PRAGMA key = 'probe-test-passphrase';");
    out.execute(
        "ATTACH DATABASE '${sourcePath.replaceAll("'", "''")}' AS plaintext KEY '';");
    print('[export] ATTACH ok');

    // Verify the attached side is plaintext and note sqlite_sequence state.
    final attachedSeq = out.select(
        "SELECT name FROM plaintext.sqlite_master WHERE type='table' AND name='sqlite_sequence'");
    final attachedBackup = out.select(
        "SELECT name FROM plaintext.sqlite_master WHERE type='table' AND name='sqlite_sequence_backup'");
    print('[export] plaintext.sqlite_sequence exists: ${attachedSeq.isNotEmpty}');
    print(
        '[export] plaintext.sqlite_sequence_backup exists: ${attachedBackup.isNotEmpty}');

    out.execute("SELECT sqlcipher_export('plaintext');");
    print('[export] sqlcipher_export SUCCEEDED');
    exportSucceeded = true;
  } on sql.SqliteException catch (e) {
    print('[export] FAILED: code=${e.extendedResultCode} '
        'message="${e.message}"');
    print('[export] Message was: ${e.message}');
    exportSucceeded = false;
  } catch (e) {
    print('[export] UNEXPECTED ERROR: $e');
    exportSucceeded = false;
  }

  // Always detach (best-effort).
  try {
    out.execute('DETACH DATABASE plaintext;');
    print('[export] DETACH ok');
  } catch (e) {
    print('[export] DETACH failed (expected if export rolled back): $e');
  }

  _section('STEP 3: inspect the destination afterward');
  final encExists = File(encPath).existsSync();
  print('[out] encrypted file exists: $encExists');
  if (encExists) {
    print('[out] encrypted file bytes: ${File(encPath).lengthSync()}');
  }
  final dest = sql.sqlite3.open(encPath);
  try {
    dest.execute("PRAGMA key = 'probe-test-passphrase';");
    _dumpMaster(dest, 'out');
    _dumpSequence(dest, 'out');
    final uv = dest.select('PRAGMA user_version');
    print('[out] user_version = ${uv.isEmpty ? '?' : uv.first[0]}');
    final integrity = dest.select('PRAGMA integrity_check');
    print('[out] integrity_check = '
        '${integrity.isEmpty ? '?' : integrity.first[0]}');
  } on sql.SqliteException catch (e) {
    print('[out] could not open/inspect destination: '
        'code=${e.extendedResultCode} message="${e.message}"');
  } finally {
    dest.dispose();
  }

  _section('STEP 4: compare sequence values (out vs source backup)');
  // Re-open the modified source copy to read the backup table.
  final src2 = sql.sqlite3.open(sourcePath);
  final backupRows = src2.select(
      'SELECT * FROM sqlite_sequence_backup ORDER BY name');
  print('[src-backup] sqlite_sequence_backup rows (${backupRows.length}):');
  for (final r in backupRows) {
    print('[src-backup]   ${r['name']} = ${r['seq']}');
  }
  src2.dispose();

  _section('STEP 5: restore sqlite_sequence_backup -> sqlite_sequence');
  final r2 = sql.sqlite3.open(sourcePath);
  var restoreSucceeded = false;
  try {
    r2.execute(
        'ALTER TABLE sqlite_sequence_backup RENAME TO sqlite_sequence;');
    print('[restore] SUCCESS: renamed back to sqlite_sequence');
    restoreSucceeded = true;
  } on sql.SqliteException catch (e) {
    print('[restore] FAILED: code=${e.extendedResultCode} '
        'message="${e.message}"');
  } catch (e) {
    print('[restore] UNEXPECTED ERROR: $e');
  }
  if (restoreSucceeded) {
    _dumpSequence(r2, 'restored');
    _dumpMaster(r2, 'restored');
  }
  r2.dispose();

  _section('SUMMARY');
  print('exportSucceeded = $exportSucceeded');
  print('renameSucceeded = true');
  print('restoreSucceeded = $restoreSucceeded');
  print('encrypted output path = $encPath');
  print('(leave encrypted output in place for inspection)');

  _finalVerify(sourcePath);
}

void _finalVerify(String sourcePath) {
  _section('FINAL VERIFY: source copy restored + original untouched');
  final f = File(sourcePath);
  if (f.existsSync()) {
    print('[final] source copy bytes = ${f.lengthSync()}');
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
