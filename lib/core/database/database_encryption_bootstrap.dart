import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../services/security_service.dart';

/// Persistent states for the one-time plaintext -> SQLCipher conversion.
///
/// The marker lives OUTSIDE the database itself (a sidecar file next to
/// `classai.db`) because the database file is replaced during conversion and
/// therefore cannot be trusted to record its own migration progress.
enum DbEncryptionState { pending, converting, complete }

/// Performs the one-time migration of an existing plaintext `classai.db` into
/// a SQLCipher-encrypted database, with crash-safe, resumable semantics.
///
/// ## Why this is needed
/// Devices already in the field have real, unencrypted data in `classai.db`.
/// Simply shipping a SQLCipher build would leave those files plaintext and
/// drift would keep reading them unencrypted. This service converts them once,
/// in place, using SQLCipher's `sqlcipher_export()` mechanism.
///
/// ## Mechanism (SQLCipher's canonical plaintext -> encrypted path)
/// SQLCipher's `rekey` only works on a database *already* opened with a key, so
/// it cannot convert an existing plaintext file. The correct operation is to
/// create a fresh encrypted database, `ATTACH` the old plaintext one (with an
/// empty key, signalling it is plaintext), and run `SELECT sqlcipher_export()`
/// to copy schema + data + `user_version` across.
///
/// ## Crash-safety (mirrors `VacuumService`'s write-then-verify-then-swap)
/// The conversion always writes to a *new* file (`classai_encrypted.db`) and
/// only swaps it into place after `PRAGMA integrity_check` and per-table
/// row-count checks pass. A kill at any point before the final swap leaves the
/// original plaintext `classai.db` untouched, so the next launch simply resumes.
/// A persistent sidecar state marker drives recovery across the small crash
/// window around the file renames.
///
/// ## Deliberate safety margin: old plaintext file is kept, not deleted
/// After a successful conversion the original plaintext database is renamed to
/// `classai_preencryption_backup_<date>.db` and left on disk INDEFINITELY. This
/// is intentional: `integrity_check` + row-counts cannot catch every subtle
/// conversion bug, so the plaintext is retained as a manual recovery fallback.
/// Removing that backup later would be a separate, deliberate manual decision —
/// it is not part of this change and must not be auto-deleted here.
class DatabaseEncryptionBootstrap {
  final SecurityService _security;

  DatabaseEncryptionBootstrap(this._security);

  static const _stateFileName = 'classai_encryption_state';
  static const _encryptedTempName = 'classai_encrypted.db';
  static const _dbFileName = 'classai.db';

  /// Tables whose row counts are compared between old and new DBs before the
  /// swap is allowed to proceed.
  static const _keyTableNames = [
    'vault_items',
    'sync_queue',
    'lessons',
    'exams',
  ];

  /// Applies the SQLCipher native-library override needed on Android.
  ///
  /// Must be called on any isolate that opens a database through
  /// `package:sqlite3` (directly or indirectly via drift) before using sqlite.
  /// This includes the main isolate and drift's background isolate.
  static void applyNativeOverrides() {
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
  }

  /// Ensures the database at [dbDirectory]/classai.db is SQLCipher-encrypted.
  ///
  /// Returns the encryption passphrase (generated and persisted on first call,
  /// never regenerated once present) so the caller can thread it into
  /// background isolates.
  ///
  /// MUST be called on the main isolate, where reading/writing
  /// `flutter_secure_storage` is safe, and BEFORE drift opens the database.
  Future<String> ensureEncrypted(String dbDirectory) async {
    applyNativeOverrides();

    final passphrase = await _security.getOrCreateDbEncryptionPassphrase();
    final dbPath = p.join(dbDirectory, _dbFileName);

    final state = _readState(dbDirectory);
    if (state == DbEncryptionState.converting) {
      await _recoverInterrupted(dbPath, dbDirectory, passphrase);
      // After recovery the database is either encrypted (skip) or the
      // interrupted run was cleaned up so we fall through to convert again.
      if (!File(dbPath).existsSync() || !_isPlaintext(dbPath)) {
        return passphrase;
      }
    }

    if (File(dbPath).existsSync() && _isPlaintext(dbPath)) {
      await _convertPlaintextToEncrypted(dbPath, dbDirectory, passphrase);
    }

    return passphrase;
  }

  /// Recovers from a conversion that was interrupted mid-way, based on the
  /// persisted [DbEncryptionState.converting] marker.
  Future<void> _recoverInterrupted(
      String dbPath, String dbDirectory, String passphrase) async {
    final dbFile = File(dbPath);
    final encryptedTemp = File(p.join(dbDirectory, _encryptedTempName));

    // Case A: the final swap already happened but the marker write was
    // interrupted -> classai.db is now encrypted. Just mark complete.
    if (dbFile.existsSync() && !_isPlaintext(dbPath)) {
      _writeState(dbDirectory, DbEncryptionState.complete);
      return;
    }

    // Case B: crash happened after the plaintext was renamed away but before
    // the encrypted temp was renamed into place. classai.db is temporarily
    // missing. If a verified encrypted temp exists, restore it.
    if (!dbFile.existsSync() &&
        encryptedTemp.existsSync() &&
        _verifiesWithKey(encryptedTemp.path, passphrase)) {
      encryptedTemp.renameSync(dbPath);
      _writeState(dbDirectory, DbEncryptionState.complete);
      return;
    }

    // Case C: crash happened before any rename. classai.db is still plaintext
    // (or the temp is incomplete). Leave state as `converting` and fall through
    // to a fresh, idempotent conversion below (the incomplete temp is deleted
    // there).
  }

  /// Converts a plaintext [dbPath] into an encrypted database at the same
  /// location, keeping the original as a dated backup.
  Future<void> _convertPlaintextToEncrypted(
      String dbPath, String dbDirectory, String passphrase) async {
    // Checkpoint any WAL so all data is consolidated into the .db file before
    // export. SQLCipher reads plaintext databases fine, but a leftover WAL
    // would be inconsistent.
    _checkpointPlaintext(dbPath);

    final stateFile = File(p.join(dbDirectory, _stateFileName));
    _writeState(dbDirectory, DbEncryptionState.converting);

    final encryptedPath = p.join(dbDirectory, _encryptedTempName);
    final encryptedFile = File(encryptedPath);

    // Best-effort cleanup of a temp file left over from a prior interrupted
    // run. Runs before any connection is opened, so it is safe to delete. Any
    // failure here is deliberately ignored; a leftover temp is harmless and is
    // overwritten on the next attempt.
    _deleteTempBestEffort(encryptedPath);

    // Read the drift schema version (PRAGMA user_version) from the plaintext so
    // it can be preserved. sqlcipher_export copies tables/indexes but the
    // user_version (which drift uses to decide migrations) is preserved
    // explicitly to avoid drift re-running migrations from scratch.
    final oldUserVersion = _readUserVersion(dbPath);

    final newDb = sql.sqlite3.open(encryptedPath);
    var converted = false;
    try {
      newDb.execute("PRAGMA key = '$passphrase';");
      newDb.execute(
          "ATTACH DATABASE '${_escapeSql(dbPath)}' AS plaintext KEY '';");

      // sqlcipher_export() is permanently broken for this schema. Direct
      // testing on a real production copy proved it fails once AUTOINCREMENT
      // tables populate sqlite_sequence, so the migration must copy the schema
      // and data manually instead of "simplifying" back to export later.
      // The FTS5 shadow-table names are hardcoded because this schema
      // currently has one FTS5 table; update this exclusion list if new FTS5
      // tables are ever added.
      final tableRows = newDb.select(
        "SELECT name, sql FROM plaintext.sqlite_master "
        "WHERE type='table' AND name NOT LIKE 'sqlite_%' "
        "AND name NOT IN ('search_index_data', 'search_index_idx', "
        "'search_index_content', 'search_index_docsize', "
        "'search_index_config') "
        'ORDER BY rowid',
      );
      for (final row in tableRows) {
        final tableName = row['name'] as String;
        final tableSql = row['sql'] as String?;
        if (tableSql == null) {
          throw StateError('CREATE TABLE SQL unexpectedly null for $tableName');
        }
        newDb.execute(tableSql);
        newDb.execute(
          'INSERT INTO main."$tableName" SELECT * FROM plaintext."$tableName";',
        );
      }

      final indexRows = newDb.select(
        "SELECT name, sql FROM plaintext.sqlite_master "
        "WHERE type='index' AND sql IS NOT NULL "
        'ORDER BY rowid',
      );
      for (final row in indexRows) {
        final indexName = row['name'] as String;
        final indexSql = row['sql'] as String?;
        if (indexSql == null) {
          throw StateError('Index SQL unexpectedly null for $indexName');
        }
        newDb.execute(indexSql);
      }

      // sqlite_sequence only exists when at least one AUTOINCREMENT table is
      // present. If the ORIGINAL plaintext database never had one, there is
      // nothing to preserve and this step is skipped entirely. Only fail if the
      // source HAD a sqlite_sequence table but the copy failed to recreate it,
      // which would indicate an actual copy failure.
      final plainSeqExists = newDb.select(
        "SELECT name FROM plaintext.sqlite_master WHERE type='table' AND name='sqlite_sequence'",
      );
      if (plainSeqExists.isNotEmpty) {
        final seqExists = newDb.select(
          "SELECT name FROM main.sqlite_master WHERE type='table' AND name='sqlite_sequence'",
        );
        if (seqExists.isEmpty) {
          throw StateError('main.sqlite_sequence does not exist after table copy.');
        }
        newDb.execute('DELETE FROM main.sqlite_sequence;');
        final seqRows = newDb.select(
          'SELECT name, seq FROM plaintext.sqlite_sequence ORDER BY name',
        );
        for (final row in seqRows) {
          final name = row['name'] as String;
          final seq = row['seq'];
          final seqValue = seq is int ? seq : int.tryParse('$seq');
          if (seqValue == null) {
            throw StateError('sqlite_sequence value unexpectedly invalid for $name');
          }
          newDb.execute(
            "INSERT INTO main.sqlite_sequence (name, seq) "
            "VALUES ('${_escapeSql(name)}', $seqValue);",
          );
        }
      }

      newDb.execute('DETACH DATABASE plaintext;');

      if (oldUserVersion != null) {
        newDb.execute('PRAGMA user_version = $oldUserVersion;');
      }

      // Verify integrity of the newly-encrypted database.
      final integrity = newDb.select('PRAGMA integrity_check');
      if (integrity.isEmpty || integrity.first[0] != 'ok') {
        throw StateError(
            'Encrypted database integrity check failed after conversion.');
      }

      // Verify the conversion by comparing key-table row counts.
      final oldDb = sql.sqlite3.open(dbPath);
      try {
        for (final table in _keyTableNames) {
          final oldCount = _tableCount(oldDb, table);
          final newCount = _tableCount(newDb, table);
          if (oldCount != newCount) {
            throw StateError(
                'Row count mismatch for "$table" during conversion: '
                'old=$oldCount new=$newCount');
          }
        }
      } finally {
        oldDb.dispose();
      }

      // All verification passed.
      converted = true;
    } finally {
      // Close the SQLite handle BEFORE any file mutation below. On Windows,
      // deleting the temp while this connection is still open throws a
      // PathAccessException that would mask the real conversion error.
      newDb.dispose();
    }

    if (!converted) {
      // Conversion failed. Remove the half-written encrypted temp (and any
      // WAL/SHM sidecars) best-effort so the real error is rethrown, not a
      // secondary file-deletion error. The original exception propagates from
      // the try block above.
      _deleteTempBestEffort(encryptedPath);
    }

    // All verification passed. Swap in place.
    final dbFile = File(dbPath);
    final backupName = 'classai_preencryption_backup_${_timestamp()}.db';
    final backupPath = p.join(dbDirectory, backupName);

    // Rename the plaintext to a dated backup FIRST. It is kept indefinitely as
    // a deliberate safety margin (see class docs) and must never be deleted
    // here. Removing it later is a separate manual decision.
    dbFile.renameSync(backupPath);
    // Then move the verified encrypted file into the canonical path.
    encryptedFile.renameSync(dbPath);

    _writeState(dbDirectory, DbEncryptionState.complete);
  }

  /// Deletes the encrypted temp database and any SQLite WAL/SHM sidecars
  /// (best-effort, never throws).
  ///
  /// Must only be called while no connection has the temp file open, otherwise
  /// Windows will raise a `PathAccessException` ("being used by another
  /// process"). This is deliberately best-effort: a leftover temp is harmless
  /// and gets overwritten on the next conversion attempt, so any failure here
  /// must not mask the real conversion error.
  void _deleteTempBestEffort(String encryptedPath) {
    for (final suffix in const ['', '-wal', '-shm']) {
      final f = File(encryptedPath + suffix);
      if (!f.existsSync()) continue;
      try {
        f.deleteSync();
      } catch (_) {
        // Best-effort only: ignore any error so the original exception (or the
        // normal flow) is not replaced by a secondary file-deletion failure.
      }
    }
  }

  /// Whether [dbPath] is a plaintext SQLite database (readable without a key).
  ///
  /// An encrypted SQLCipher database cannot be read without the correct key and
  /// throws `SqliteException` when touched. A plaintext database reads fine.
  bool _isPlaintext(String dbPath) {
    final db = sql.sqlite3.open(dbPath);
    try {
      db.select('SELECT name FROM sqlite_master LIMIT 1');
      return true;
    } on sql.SqliteException {
      return false;
    } finally {
      db.dispose();
    }
  }

  /// Whether [dbPath] opens successfully with [passphrase] (used for recovery).
  bool _verifiesWithKey(String dbPath, String passphrase) {
    try {
      final db = sql.sqlite3.open(dbPath);
      try {
        db.execute("PRAGMA key = '$passphrase';");
        final rows = db.select('PRAGMA integrity_check');
        return rows.isNotEmpty && rows.first[0] == 'ok';
      } finally {
        db.dispose();
      }
    } on sql.SqliteException {
      return false;
    }
  }

  void _checkpointPlaintext(String dbPath) {
    final db = sql.sqlite3.open(dbPath);
    try {
      db.execute('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (_) {
      // Not in WAL mode (or journaling cannot be truncated); this is harmless.
    } finally {
      db.dispose();
    }
  }

  int? _readUserVersion(String dbPath) {
    final db = sql.sqlite3.open(dbPath);
    try {
      final rows = db.select('PRAGMA user_version');
      if (rows.isEmpty) return null;
      final value = rows.first[0];
      return value is int ? value : int.tryParse('$value');
    } catch (_) {
      return null;
    } finally {
      db.dispose();
    }
  }

  int _tableCount(sql.Database db, String table) {
    final rows = db.select('SELECT COUNT(*) AS c FROM "$table"');
    if (rows.isEmpty) return 0;
    final value = rows.first[0];
    return value is int ? value : int.tryParse('$value') ?? 0;
  }

  DbEncryptionState _readState(String dbDirectory) {
    final stateFile = File(p.join(dbDirectory, _stateFileName));
    if (!stateFile.existsSync()) return DbEncryptionState.pending;
    final value = stateFile.readAsStringSync().trim();
    return DbEncryptionState.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DbEncryptionState.pending,
    );
  }

  void _writeState(String dbDirectory, DbEncryptionState state) {
    final stateFile = File(p.join(dbDirectory, _stateFileName));
    stateFile.writeAsStringSync(state.name);
  }

  /// Escape a path for embedding in a SQL string literal (doubles single
  /// quotes).
  String _escapeSql(String value) => value.replaceAll("'", "''");

  String _timestamp() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final h = now.hour.toString().padLeft(2, '0');
    final min = now.minute.toString().padLeft(2, '0');
    final s = now.second.toString().padLeft(2, '0');
    return '${y}${m}${d}_${h}${min}${s}';
  }
}
