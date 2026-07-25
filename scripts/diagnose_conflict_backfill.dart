// scripts/diagnose_conflict_backfill.dart
//
// ONE-TIME DIAGNOSTIC SCRIPT
// Run with: dart run scripts/diagnose_conflict_backfill.dart
// (Must be run from project root; Dart SDK required.)
//
// Purpose: Count how many existing conflict rows with NULL local_value/remote_value
// are recoverable by looking up the *current* state of the referenced records,
// vs. how many are genuinely unrecoverable (records deleted or never existed).
//
// Uses sqlite3 CLI tool directly (same pattern as backfill_null_conflicts.dart)
// to avoid Drift API dependency issues in standalone scripts.

import 'dart:io';

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const String _sqlite3Path =
    r'C:\Users\Yene\AppData\Local\Android\Sdk\platform-tools\sqlite3.exe';

/// Maps a `record_type` string (as stored in the conflicts table) to its
/// corresponding table name and primary-key column for lookups.
///
/// Most tables use `id` as their local PK; teachers and schools use `local_id`.
const Map<String, ({String tableName, String pkColumn})> _TABLE_MAP = {
  'lessons': (tableName: 'lessons', pkColumn: 'id'),
  'exams': (tableName: 'exams', pkColumn: 'id'),
  'scheme_of_work': (tableName: 'scheme_of_work', pkColumn: 'id'),
  'vault_items': (tableName: 'vault_items', pkColumn: 'id'),
  'subjects': (tableName: 'subjects', pkColumn: 'id'),
  'progress_logs': (tableName: 'progress_logs', pkColumn: 'id'),
  'teachers': (tableName: 'teachers', pkColumn: 'local_id'),
  'schools': (tableName: 'schools', pkColumn: 'local_id'),
};

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
String _dbPath(String? override) {
  if (override != null && File(override).existsSync()) return override;
  final docs =
      '${Platform.environment['USERPROFILE'] ?? '.'}\\Documents\\classai.db';
  if (File(docs).existsSync()) return docs;
  return 'classai.db';
}

Future<ProcessResult> _sql(String dbPath, String sql) async {
  return Process.run(_sqlite3Path, [dbPath, sql], runInShell: false);
}

/// Returns the raw stdout lines from a SQL query, trimming whitespace.
Future<List<String>> _queryRows(String dbPath, String sql) async {
  final result = await _sql(dbPath, sql);
  if (result.exitCode != 0) {
    throw Exception('SQL error (exit ${result.exitCode}): ${result.stderr}');
  }
  final out = result.stdout.toString().trim();
  if (out.isEmpty) return [];
  return out.split('\n');
}

/// Checks if a record exists and is not soft-deleted in the given table.
Future<bool> _recordExists(
  String dbPath,
  String tableName,
  String pkColumn,
  int localId,
) async {
  final rows = await _queryRows(dbPath,
      'SELECT 1 FROM "$tableName" '
      'WHERE "$pkColumn" = $localId '
      'AND (is_deleted IS NULL OR is_deleted = 0)');
  return rows.isNotEmpty;
}

/// Returns the serverId (UUID) of a local record, or null if absent.
Future<String?> _getServerId(
  String dbPath,
  String tableName,
  String pkColumn,
  int localId,
) async {
  final rows = await _queryRows(dbPath,
      'SELECT server_id FROM "$tableName" '
      'WHERE "$pkColumn" = $localId '
      'AND server_id IS NOT NULL AND server_id != \'\'');
  if (rows.isEmpty) return null;
  final sid = rows.first.trim();
  return sid.isEmpty || sid.toLowerCase() == 'null' ? null : sid;
}

// ---------------------------------------------------------------------------
// Main
// ---------------------------------------------------------------------------
void main(List<String> args) async {
  final dbPath = _dbPath(args.isNotEmpty ? args[0] : null);
  if (!File(dbPath).existsSync()) {
    print('ERROR: Database not found at: $dbPath');
    print(
        'Usage: dart run scripts/diagnose_conflict_backfill.dart [path/to/classai.db]');
    exit(1);
  }

  print('=== CONFLICT BACKFILL DIAGNOSTIC ===');
  print('Database: $dbPath');
  print('');

  // Fetch all conflict rows where local_value OR remote_value IS NULL
  List<String> nullRowLines;
  try {
    nullRowLines = await _queryRows(dbPath,
        'SELECT id, record_type, record_local_id, '
        "CASE WHEN local_value IS NULL THEN 'NULL' ELSE 'OK' END AS local, "
        "CASE WHEN remote_value IS NULL THEN 'NULL' ELSE 'OK' END AS remote "
        'FROM conflicts '
        'WHERE local_value IS NULL OR remote_value IS NULL');
  } catch (e) {
    print('ERROR querying conflicts table: $e');
    exit(1);
  }

  print(
      'Total conflict rows with NULL local_value/remote_value: ${nullRowLines.length}');
  print('');

  if (nullRowLines.isEmpty) {
    print('Nothing to do — no NULL-valued conflict rows found.');
    return;
  }

  // Parse each line: format is "id|record_type|record_local_id|local|remote"
  final List<({int id, String recordType, int recordLocalId})> nullRows = [];
  for (final line in nullRowLines) {
    final parts = line.split('|');
    if (parts.length < 3) continue;
    final id = int.tryParse(parts[0].trim());
    final recordLocalId = int.tryParse(parts[2].trim());
    if (id == null || recordLocalId == null) continue;
    nullRows.add((
      id: id,
      recordType: parts[1].trim(),
      recordLocalId: recordLocalId,
    ));
  }

  // Categorize each row
  int recoverableLocal = 0;
  int recoverableRemote = 0;
  int unrecoverableLocal = 0;
  int unrecoverableRemote = 0;

  final Map<String, int> byTable = {};
  final List<String> detailLines = [];

  for (final conflict in nullRows) {
    byTable[conflict.recordType] =
        (byTable[conflict.recordType] ?? 0) + 1;

    final tableInfo = _TABLE_MAP[conflict.recordType];
    if (tableInfo == null) {
      detailLines.add(
        '  #${conflict.id}: UNKNOWN table "${conflict.recordType}" — '
        'cannot inspect',
      );
      unrecoverableLocal++;
      unrecoverableRemote++;
      continue;
    }

    // --- LOCAL SIDE: check if the record exists ---
    final localExists =
        await _recordExists(dbPath, tableInfo.tableName, tableInfo.pkColumn,
            conflict.recordLocalId);

    if (localExists) {
      recoverableLocal++;
      detailLines.add(
        '  #${conflict.id}: ${conflict.recordType}(localId=${conflict.recordLocalId}) '
        '→ LOCAL exists ✓',
      );
    } else {
      unrecoverableLocal++;
      detailLines.add(
        '  #${conflict.id}: ${conflict.recordType}(localId=${conflict.recordLocalId}) '
        '→ LOCAL MISSING/DELETED ✗',
      );
    }

    // --- REMOTE SIDE: check if the local record has a serverId ---
    final serverId = await _getServerId(dbPath, tableInfo.tableName,
        tableInfo.pkColumn, conflict.recordLocalId);

    if (serverId != null) {
      recoverableRemote++;
      detailLines.add(
        '    REMOTE: serverId=$serverId (record was synced → supabase lookup possible) ✓',
      );
    } else {
      unrecoverableRemote++;
      detailLines.add(
        '    REMOTE: NO serverId (never synced, or record deleted locally) ✗',
      );
    }
  }

  // Print summary
  print('');
  print('=== RESULTS ===');
  print('');
  print('Breakdown by table:');
  byTable.forEach((table, count) {
    print('  $table: $count');
  });
  print('');

  final totalLocal = recoverableLocal + unrecoverableLocal;
  print('--- LOCAL VALUE backfill ---');
  print(
      '  Records still present in Drift (recoverable):  $recoverableLocal / $totalLocal');
  print(
      '  Records missing/deleted (unrecoverable):       $unrecoverableLocal / $totalLocal');

  final totalRemote = recoverableRemote + unrecoverableRemote;
  print('--- REMOTE VALUE backfill ---');
  print(
      '  Has serverId (recoverable via Supabase query): $recoverableRemote / $totalRemote');
  print(
      '  No serverId (unrecoverable):                   $unrecoverableRemote / $totalRemote');
  print('');

  print('--- DETAIL ---');
  for (final line in detailLines) {
    print(line);
  }
  print('');
  print('=== RECOMMENDATION ===');
  if (recoverableLocal > 0 || recoverableRemote > 0) {
    print(
      'At least some rows CAN be backfilled from current state. '
      'See the architectural analysis for the honest-backfill approach.',
    );
  }
  if (unrecoverableLocal > 0 || unrecoverableRemote > 0) {
    print(
      '${unrecoverableLocal + unrecoverableRemote} conflict(s) CANNOT be backfilled '
      '(missing local records and/or no serverId). These should be auto-resolved '
      '("cleared with note") rather than left dangling.',
    );
  }
}
