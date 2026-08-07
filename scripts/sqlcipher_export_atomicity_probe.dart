// INVESTIGATION-ONLY probe #2 (no fix). Confirms sqlcipher_export atomicity.
//
// Runs the normal plaintext -> encrypted ATTACH + sqlcipher_export flow
// against an UNMODIFIED copy (so it reproduces the real "no such table:
// main.sqlite_sequence" failure) and then inspects the destination to
// determine whether the failed export rolled back atomically.
//
// Also probes whether sqlite_sequence is the FIRST thing export touches by
// using a synthetic source whose AUTOINCREMENT table sorts LAST vs the schema.

import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

const String kCipherDll =
    r'C:\Users\Yene\classai\build\windows\x64\runner\Debug\sqlite3.dll';

DynamicLibrary _openCipherDll() => DynamicLibrary.open(kCipherDll);

void _section(String s) => print('\n===== $s =====');

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run scripts/sqlcipher_export_atomicity_probe.dart '
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

  open.overrideFor(OperatingSystem.windows, _openCipherDll);

  final probe = sql.sqlite3.openInMemory();
  final ver = probe.select('PRAGMA cipher_version').first[0];
  print('SQLCipher cipher_version = $ver');
  probe.dispose();

  final dir = p.dirname(sourcePath);
  final encPath = p.join(dir, 'probe2_out_encrypted.db');
  if (File(encPath).existsSync()) File(encPath).deleteSync();

  _section('PROBE 2A: plain export against unmodified copy (repro failure)');
  final out = sql.sqlite3.open(encPath);
  try {
    out.execute("PRAGMA key = 'probe2-pass';");
    out.execute(
        "ATTACH DATABASE '${sourcePath.replaceAll("'", "''")}' AS plaintext KEY '';");
    print('[2A] ATTACH ok');
    // Inspect destination BEFORE export so we can compare.
    final before = out
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'])
        .toList();
    print('[2A] destination tables BEFORE export (${before.length}): $before');

    try {
      out.execute("SELECT sqlcipher_export('plaintext');");
      print('[2A] export SUCCEEDED (unexpected on real copy)');
    } on sql.SqliteException catch (e) {
      print('[2A] export FAILED: code=${e.extendedResultCode} '
          'message="${e.message}"');
    }
  } on sql.SqliteException catch (e) {
    print('[2A] setup failed: code=${e.extendedResultCode} '
        'message="${e.message}"');
  }

  // Detach best-effort, then close.
  try {
    out.execute('DETACH DATABASE plaintext;');
  } catch (_) {}
  out.dispose();

  _section('PROBE 2A: destination file state AFTER failed export');
  print('[2A] encrypted file exists: ${File(encPath).existsSync()}');
  if (File(encPath).existsSync()) {
    print('[2A] encrypted file bytes after failure: ${File(encPath).lengthSync()}');
  }
  final reopen = sql.sqlite3.open(encPath);
  try {
    reopen.execute("PRAGMA key = 'probe2-pass';");
    final tables = reopen
        .select("SELECT name FROM sqlite_master WHERE type='table'")
        .map((r) => r['name'])
        .toList();
    print('[2A] destination tables AFTER export (${tables.length}): $tables');
    final integrity = reopen.select('PRAGMA integrity_check');
    print('[2A] integrity = ${integrity.isEmpty ? "?" : integrity.first[0]}');
  } on sql.SqliteException catch (e) {
    print('[2A] reopen/inspect failed: code=${e.extendedResultCode} '
        'message="${e.message}"');
  } finally {
    reopen.dispose();
  }

  _section('PROBE 2B: ordering test - is sqlite_sequence touched first?');
  // Build a synthetic source where the AUTOINCREMENT table sorts LAST
  // alphabetically. If export fails with the sqlite_sequence error and the
  // destination rolled back to 0 tables, that's consistent with a single
  // transaction. To probe ordering we instead make the AUTOINCREMENT table the
  // ONLY user table (so nothing else can "fail first").
  final synthPath = p.join(dir, 'probe2_synth.db');
  if (File(synthPath).existsSync()) File(synthPath).deleteSync();
  final synth = sql.sqlite3.open(synthPath);
  synth.execute('CREATE TABLE zzz (id INTEGER PRIMARY KEY AUTOINCREMENT, v TEXT);');
  synth.execute("INSERT INTO zzz (v) VALUES ('a');");
  synth.execute("INSERT INTO zzz (v) VALUES ('b');");
  synth.dispose();

  final encPath2 = p.join(dir, 'probe2_synth_out.db');
  if (File(encPath2).existsSync()) File(encPath2).deleteSync();
  final out2 = sql.sqlite3.open(encPath2);
  try {
    out2.execute("PRAGMA key = 'probe2-pass';");
    out2.execute(
        "ATTACH DATABASE '${synthPath.replaceAll("'", "''")}' AS plaintext KEY '';");
    try {
      out2.execute("SELECT sqlcipher_export('plaintext');");
      print('[2B] synth export SUCCEEDED');
    } on sql.SqliteException catch (e) {
      print('[2B] synth export FAILED: code=${e.extendedResultCode} '
          'message="${e.message}"');
    }
  } catch (e) {
    print('[2B] synth setup failed: $e');
  }
  try {
    out2.execute('DETACH DATABASE plaintext;');
  } catch (_) {}
  out2.dispose();
  print('[2B] synth out exists: ${File(encPath2).existsSync()} '
      'bytes=${File(encPath2).existsSync() ? File(encPath2).lengthSync() : -1}');
  if (File(encPath2).existsSync() && File(encPath2).lengthSync() > 0) {
    final o = sql.sqlite3.open(encPath2);
    try {
      o.execute("PRAGMA key = 'probe2-pass';");
      final tables = o
          .select("SELECT name FROM sqlite_master WHERE type='table'")
          .map((r) => r['name'])
          .toList();
      print('[2B] synth out tables: $tables');
      final seq = o.select('SELECT * FROM sqlite_sequence');
      print('[2B] synth out sqlite_sequence rows: ${seq.length}');
      for (final r in seq) {
        print('[2B]   ${r['name']} = ${r['seq']}');
      }
      final zcount = o.select('SELECT COUNT(*) AS c FROM zzz').first[0];
      print('[2B] synth out zzz count = $zcount');
    } finally {
      o.dispose();
    }
  }
}
