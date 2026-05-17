import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'tables/schools.dart';
import 'tables/teachers.dart';
import 'tables/subjects.dart';
import 'tables/lessons.dart';
import 'tables/scheme_of_work.dart';
import 'tables/exams.dart';
import 'tables/progress_logs.dart';
import 'tables/vault_items.dart';
import 'tables/security_config.dart';
import 'tables/sync_queue.dart';
import 'tables/sync_queue_snapshot.dart';
import 'tables/version_hashes.dart';
import 'tables/conflicts.dart';
import 'tables/payment_events.dart';
import 'tables/recovery_codes.dart';
import 'tables/pending_recovery_requests.dart';
import 'tables/teacher_devices.dart';
import 'tables/scheme_generation_queue.dart';
import 'tables/pdf_cache.dart';
import 'tables/teacher_subjects.dart';

import 'daos/security_config_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'daos/payment_events_dao.dart';
import 'daos/vault_items_dao.dart';
import 'daos/pdf_cache_dao.dart';
import 'daos/teacher_subjects_dao.dart';

part 'database.g.dart'; // generated

@DriftDatabase(tables: [
  Schools,
  Teachers,
  Subjects,
  Lessons,
  SchemeOfWork,
  Exams,
  ProgressLogs,
  VaultItems,
  SecurityConfig,
  SyncQueue,
  SyncQueueSnapshot,
  VersionHashes,
  Conflicts,
  PaymentEvents,
  RecoveryCodes,
  PendingRecoveryRequests,
  TeacherDevices,
  SchemeGenerationQueue,
  PdfCache,
  TeacherSubjects,
])
class AppDatabase extends _$AppDatabase {
  SecurityConfigDao get securityConfigDao => SecurityConfigDao(this);
  SyncQueueDao get syncQueueDao => SyncQueueDao(this);
  PaymentEventsDao get paymentEventsDao => PaymentEventsDao(this);
  VaultItemsDao get vaultItemsDao => VaultItemsDao(this);
  PdfCacheDao get pdfCacheDao => PdfCacheDao(this);
  TeacherSubjectsDao get teacherSubjectsDao => TeacherSubjectsDao(this);

  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 6;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = p.join(dbFolder.path, 'classai.db');

      return NativeDatabase.createInBackground(
        File(file),
        // CRITICAL: This uses SQLite Online Backup API internally
      );
    });
  }

  // Run after database opens
  Future<void> initialize() async {
    await customStatement('PRAGMA journal_mode=WAL');
    await customStatement('PRAGMA foreign_keys=ON');

    // Integrity check
    final result = await customSelect('PRAGMA integrity_check').get();
    final ok = result.map((r) => r.read<String>('integrity_check')).first;
    if (ok != 'ok') {
      throw DatabaseIntegrityException('Database integrity check failed: $ok');
    }

    // Create FTS5 virtual table for search
    await customStatement('''
      CREATE VIRTUAL TABLE IF NOT EXISTS search_index USING fts5(
        content_type,    -- 'lesson', 'exam', 'vault_item'
        record_local_id,
        title,
        body,
        tokenize='porter unicode61'
      )
    ''');
  }

  // Migration support
  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await customStatement(
              'ALTER TABLE security_config ADD COLUMN last_realtime_event_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE version_hashes ADD COLUMN snapshot_json TEXT NULL',
            );
            await customStatement(
              "ALTER TABLE conflicts ADD COLUMN record_type TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              'ALTER TABLE conflicts ADD COLUMN record_local_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              "ALTER TABLE conflicts ADD COLUMN conflicting_fields TEXT NOT NULL DEFAULT '[]'",
            );
            await customStatement(
              "ALTER TABLE conflicts ADD COLUMN resolution TEXT NOT NULL DEFAULT 'unresolved'",
            );
            await customStatement(
              'ALTER TABLE conflicts ADD COLUMN notified INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              "ALTER TABLE conflicts ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP",
            );
            await customStatement(
              "ALTER TABLE conflicts ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP",
            );
          }
          if (from < 3) {
            // Expand lessons table from bare id to full schema
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN subject TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN class_level TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN week INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN topic TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN difficulty TEXT NOT NULL DEFAULT 'medium'",
            );
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN blooms_verbs TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN curriculum TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN content TEXT NOT NULL DEFAULT '{}'",
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
            // Expand exams table from bare id to full schema
            await customStatement(
              "ALTER TABLE exams ADD COLUMN subject TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE exams ADD COLUMN class_level TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE exams ADD COLUMN topic TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE exams ADD COLUMN difficulty TEXT NOT NULL DEFAULT 'medium'",
            );
            await customStatement(
              "ALTER TABLE exams ADD COLUMN curriculum TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              "ALTER TABLE exams ADD COLUMN content TEXT NOT NULL DEFAULT '{}'",
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
          }
          if (from < 4) {
            // Add email and attempted_at columns to pending_recovery_requests
            // for rate limiting (3 attempts/hour per teacher).
            await customStatement(
              'ALTER TABLE pending_recovery_requests ADD COLUMN email TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              'ALTER TABLE pending_recovery_requests ADD COLUMN attempted_at TEXT NOT NULL DEFAULT \'1970-01-01T00:00:00.000\'',
            );
          }
          if (from < 5) {
            // Add PDF cache table
            await customStatement('''
              CREATE TABLE IF NOT EXISTS pdf_cache (
                cache_key TEXT NOT NULL PRIMARY KEY,
                pdf_data BLOB NOT NULL,
                cached_at TEXT NOT NULL
              )
            ''');
          }
          if (from < 6) {
            // Create teacher_subjects join table for teacher-subject assignments
            await customStatement('''
              CREATE TABLE IF NOT EXISTS teacher_subjects (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                teacher_local_id INTEGER NOT NULL REFERENCES teachers(local_id),
                subject_id INTEGER NOT NULL REFERENCES subjects(id)
              )
            ''');
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys=ON');

          // Seed the SecurityConfig singleton row if it doesn't exist
          final result =
              await customSelect('SELECT COUNT(*) as c FROM security_config')
                  .getSingle();
          if (result.read<int>('c') == 0) {
            final deviceId = const Uuid().v4();
            await into(securityConfig).insert(
              SecurityConfigCompanion.insert(currentDeviceId: deviceId),
            );
          }
        },
      );
}

class DatabaseIntegrityException implements Exception {
  final String message;
  DatabaseIntegrityException(this.message);
}
