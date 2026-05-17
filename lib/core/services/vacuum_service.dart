import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import '../database/database.dart';

/// Safe VACUUM implementation for ClassAI.
///
/// ## Why Safe VACUUM?
/// Standard SQLite VACUUM rewrites the entire database file, which can
/// corrupt the database if interrupted (power loss, app crash). Since
/// ClassAI targets Nigerian schools with unreliable power, we use a
/// multi-step safe approach:
///
/// 1. Checkpoint WAL to consolidate all data into .db file
/// 2. Verify checkpoint completed (busy = 0)
/// 3. Copy .db file (WAL is now empty, safe to just copy .db)
/// 4. Run VACUUM in background isolate on the temp copy
/// 5. Schedule replacement on next cold start
///
/// ## When to Run
/// - After a large sync operation
/// - When free pages > 20% of total pages
/// - Manual trigger from Settings
/// - Once per month (lastVacuumDate check)
class VacuumService {
  final AppDatabase _db;

  VacuumService(this._db);

  /// Run a safe VACUUM operation.
  ///
  /// Returns true if the VACUUM was scheduled successfully
  /// (will be applied on next cold start).
  Future<bool> safeVacuum() async {
    // 1. Checkpoint WAL to consolidate all data into .db file
    await _db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

    // 2. Verify checkpoint completed (busy = 0)
    final checkpointResult =
        await _db.customSelect('PRAGMA wal_checkpoint').get();
    // PRAGMA wal_checkpoint returns columns: busy, log, checkpointed
    // We need to check if busy is 0
    final busy = _getIntColumn(checkpointResult, 'busy');
    if (busy > 0) {
      // WAL still has pending data, abort VACUUM, retry after next sync
      return false;
    }

    // 3. Copy .db file (WAL is now empty, safe to just copy .db)
    final originalPath = await getDatabasePath();
    final originalFile = File(originalPath);
    if (!originalFile.existsSync()) {
      // In-memory database or file doesn't exist yet; cannot VACUUM
      return false;
    }
    final tempPath = '${originalPath}_vacuum';
    originalFile.copySync(tempPath);

    // 4. Run VACUUM in background isolate on the temp copy
    final success = await Isolate.run(() async {
      final vacDb = sql.sqlite3.open(tempPath);
      try {
        vacDb.execute('VACUUM');
        vacDb.execute('PRAGMA integrity_check');
        return true;
      } catch (_) {
        return false;
      } finally {
        vacDb.dispose();
      }
    });

    if (success) {
      // 5. Schedule replacement on next cold start
      await _db.securityConfigDao.updateConfig(
        pendingDbReplacement: true,
        vacuumedDbPath: tempPath,
        lastVacuumDate: DateTime.now(),
      );
    }

    return success;
  }

  /// Apply the vacuumed database replacement on cold start.
  ///
  /// Should be called from [AppDatabase.initialize] or app startup.
  Future<bool> applyPendingReplacement() async {
    final config = await _db.securityConfigDao.get();
    if (!config.pendingDbReplacement || config.vacuumedDbPath == null) {
      return false;
    }

    final vacPath = config.vacuumedDbPath!;
    final vacFile = File(vacPath);
    if (!vacFile.existsSync()) {
      // Vacuumed file was deleted, clear the flag
      await _db.securityConfigDao.updateConfig(
        pendingDbReplacement: false,
        vacuumedDbPath: null,
      );
      return false;
    }

    // Verify integrity of the vacuumed database
    final integrityOk = await Isolate.run(() {
      final db = sql.sqlite3.open(vacPath);
      try {
        final results = db.select('PRAGMA integrity_check');
        for (final row in results) {
          if (row[0] != 'ok') return false;
        }
        return true;
      } catch (_) {
        return false;
      } finally {
        db.dispose();
      }
    });

    if (!integrityOk) {
      // Vacuumed database is corrupted, discard it
      vacFile.deleteSync();
      await _db.securityConfigDao.updateConfig(
        pendingDbReplacement: false,
        vacuumedDbPath: null,
      );
      return false;
    }

    // Replace the original with the vacuumed copy
    final originalPath = await getDatabasePath();
    vacFile.copySync(originalPath);

    // Clean up
    vacFile.deleteSync();

    await _db.securityConfigDao.updateConfig(
      pendingDbReplacement: false,
      vacuumedDbPath: null,
    );

    return true;
  }

  /// Check if VACUUM is needed based on free page ratio.
  Future<bool> isVacuumNeeded() async {
    try {
      final result = await _db.customSelect('PRAGMA freelist_count').get();
      final freePages = _getIntColumn(result, 'freelist_count');
      final totalResult =
          await _db.customSelect('PRAGMA page_count').get();
      final totalPages = _getIntColumn(totalResult, 'page_count');

      if (totalPages == 0) return false;

      final freeRatio = freePages / totalPages;
      return freeRatio > 0.2; // > 20% free pages
    } catch (_) {
      return false;
    }
  }

  /// Get the database file path.
  Future<String> getDatabasePath() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return p.join(dbFolder.path, 'classai.db');
  }

  /// Helper to read an int column from a PRAGMA result.
  int _getIntColumn(List<dynamic> rows, String column) {
    if (rows.isEmpty) return 0;
    final first = rows.first;
    if (first is Map<String, dynamic>) {
      return (first[column] as num?)?.toInt() ?? 0;
    }
    return 0;
  }
}
