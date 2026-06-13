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
import 'tables/terms.dart';
import 'tables/audit_logs.dart';

import 'daos/security_config_dao.dart';
import 'daos/sync_queue_dao.dart';
import 'daos/payment_events_dao.dart';
import 'daos/vault_items_dao.dart';
import 'daos/pdf_cache_dao.dart';
import 'daos/teacher_subjects_dao.dart';
import 'daos/terms_dao.dart';
import 'daos/teacher_devices_dao.dart';
import 'daos/subjects_dao.dart';
import 'daos/pending_recovery_requests_dao.dart';
import 'daos/schools_dao.dart';
import 'daos/teachers_dao.dart';
import 'daos/lessons_dao.dart';
import 'daos/exams_dao.dart';
import 'daos/progress_logs_dao.dart';
import 'daos/scheme_of_work_dao.dart';
import 'daos/audit_logs_dao.dart';

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
  Terms,
  AuditLogs,
])
class AppDatabase extends _$AppDatabase {
  SecurityConfigDao get securityConfigDao => SecurityConfigDao(this);
  SyncQueueDao get syncQueueDao => SyncQueueDao(this);
  PaymentEventsDao get paymentEventsDao => PaymentEventsDao(this);
  VaultItemsDao get vaultItemsDao => VaultItemsDao(this);
  PdfCacheDao get pdfCacheDao => PdfCacheDao(this);
  TeacherSubjectsDao get teacherSubjectsDao => TeacherSubjectsDao(this);
  TeacherDevicesDao get teacherDevicesDao => TeacherDevicesDao(this);
  SubjectsDao get subjectsDao => SubjectsDao(this);
  PendingRecoveryRequestsDao get pendingRecoveryRequestsDao =>
      PendingRecoveryRequestsDao(this);
  SchoolsDao get schoolsDao => SchoolsDao(this);
  TeachersDao get teachersDao => TeachersDao(this);
  LessonsDao get lessonsDao => LessonsDao(this);
  ExamsDao get examsDao => ExamsDao(this);
  ProgressLogsDao get progressLogsDao => ProgressLogsDao(this);
  SchemeOfWorkDao get schemeOfWorkDao => SchemeOfWorkDao(this);
  TermsDao get termsDao => TermsDao(this);
  AuditLogsDao get auditLogsDao => AuditLogsDao(this);

  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 19;

  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = p.join(dbFolder.path, 'classai.db');

      return NativeDatabase.createInBackground(
        File(file),
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
  
    /// Removes duplicate teacher rows that share the same non-null [serverId],
    /// keeping only the row with the lowest [localId] for each serverId.
    ///
    /// Previous buggy sync runs (before school_id filtering was added) could
    /// insert the same teacher multiple times because there was no unique
    /// constraint on the server_id column. This method cleans up any such
    /// duplicates in a single pass using raw SQL.
    Future<void> deduplicateTeachers() async {
      final dupRows = await customSelect(
        'SELECT server_id, COUNT(*) AS cnt '
        'FROM teachers '
        'WHERE server_id IS NOT NULL '
        'GROUP BY server_id '
        'HAVING COUNT(*) > 1',
      ).get();
  
      if (dupRows.isEmpty) return;
  
      for (final row in dupRows) {
        final serverId = row.data['server_id'] as String;
  
        final idRows = await customSelect(
          'SELECT local_id FROM teachers '
          'WHERE server_id = ? '
          'ORDER BY local_id ASC',
          variables: [Variable(serverId)],
        ).get();
  
        if (idRows.length <= 1) continue;
  
        final ids = idRows.map((r) => r.data['local_id'] as int).toList();
        final deleteIds = ids.skip(1).toList();
  
        await customStatement(
          'DELETE FROM teachers WHERE local_id IN (${deleteIds.join(',')})',
        );
      }
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
            await customStatement(
              'ALTER TABLE conflicts ADD COLUMN local_value TEXT NULL',
            );
            await customStatement(
              'ALTER TABLE conflicts ADD COLUMN remote_value TEXT NULL',
            );
          }
          if (from < 3) {
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
            await customStatement(
              'ALTER TABLE pending_recovery_requests ADD COLUMN email TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              'ALTER TABLE pending_recovery_requests ADD COLUMN attempted_at TEXT NOT NULL DEFAULT \'1970-01-01T00:00:00.000\'',
            );
          }
          if (from < 5) {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS pdf_cache (
                cache_key TEXT NOT NULL PRIMARY KEY,
                pdf_data BLOB NOT NULL,
                cached_at TEXT NOT NULL
              )
            ''');
          }
          if (from < 6) {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS teacher_subjects (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                teacher_local_id INTEGER NOT NULL REFERENCES teachers(local_id),
                subject_id INTEGER NOT NULL REFERENCES subjects(id)
              )
            ''');
          }
          if (from < 7) {
            await customStatement(
              'ALTER TABLE schools ADD COLUMN expiry_date INTEGER',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN content_hash TEXT',
            );
          }
          if (from < 8) {
            await customStatement('''
              CREATE TABLE IF NOT EXISTS terms (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                start_date TEXT NOT NULL,
                end_date TEXT NOT NULL,
                academic_year TEXT NOT NULL,
                term_number INTEGER NOT NULL,
                is_current INTEGER NOT NULL DEFAULT 0,
                school_local_id INTEGER NOT NULL REFERENCES schools(local_id),
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
              )
            ''');
          }
          if (from < 9) {
            // Add columns to recovery_codes for USSD recovery flow.
            await customStatement(
              'ALTER TABLE recovery_codes ADD COLUMN phone_number TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              'ALTER TABLE recovery_codes ADD COLUMN code TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              'ALTER TABLE recovery_codes ADD COLUMN expires_at TEXT NOT NULL DEFAULT \'1970-01-01T00:00:00.000\'',
            );
            await customStatement(
              'ALTER TABLE recovery_codes ADD COLUMN used INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE recovery_codes ADD COLUMN teacher_local_id INTEGER',
            );
            await customStatement(
              'ALTER TABLE recovery_codes ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
          }
          if (from < 10) {
            // email and attempted_at columns were added to pending_recovery_requests
            // in migration 4 but were missing from the Drift table definition.
            // They already exist in the database; this empty migration acknowledges
            // the schema version bump so Drift matches the table definition.
          }
          if (from < 11) {
            await customStatement(
              'ALTER TABLE schools ADD COLUMN activation_code TEXT',
            );
          }
          if (from < 12) {
            // Add sync columns to lessons table
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN server_id TEXT',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN update_counter INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN last_modified_by TEXT',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN teacher_server_id TEXT',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN school_server_id TEXT',
            );
            await customStatement(
              'ALTER TABLE lessons ADD COLUMN is_unlocked INTEGER NOT NULL DEFAULT 0',
            );
            // Add sync columns to exams table
            await customStatement(
              'ALTER TABLE exams ADD COLUMN server_id TEXT',
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN update_counter INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN last_modified_by TEXT',
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN teacher_server_id TEXT',
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN school_server_id TEXT',
            );
            await customStatement(
              'ALTER TABLE exams ADD COLUMN is_unlocked INTEGER NOT NULL DEFAULT 0',
            );
            // Expand sync_queue_snapshot stub table
            await customStatement(
              'ALTER TABLE sync_queue_snapshot ADD COLUMN snapshot_data TEXT NOT NULL DEFAULT \'{}\'',
            );
            await customStatement(
              'ALTER TABLE sync_queue_snapshot ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
            // Expand scheme_of_work stub table
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN server_id TEXT',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN school_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN subject_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN term TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN week_number INTEGER NOT NULL DEFAULT 1',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN topic TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN objectives TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN update_counter INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
            // Expand scheme_generation_queue stub table
            await customStatement(
              'ALTER TABLE scheme_generation_queue ADD COLUMN school_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE scheme_generation_queue ADD COLUMN subject_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE scheme_generation_queue ADD COLUMN term TEXT NOT NULL DEFAULT \'\'',
            );
            await customStatement(
              "ALTER TABLE scheme_generation_queue ADD COLUMN status TEXT NOT NULL DEFAULT 'pending'",
            );
            await customStatement(
              'ALTER TABLE scheme_generation_queue ADD COLUMN error_message TEXT',
            );
            await customStatement(
              'ALTER TABLE scheme_generation_queue ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
            await customStatement(
              'ALTER TABLE scheme_generation_queue ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP',
            );
          }
          if (from < 13) {
            // Add columns to teachers table for device tracking
            await customStatement(
              'ALTER TABLE teachers ADD COLUMN current_device_id TEXT',
            );
            // Add columns to security_config table for daily counters
            await customStatement(
              'ALTER TABLE security_config ADD COLUMN daily_generations INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE security_config ADD COLUMN daily_generation_date TEXT',
            );
            await customStatement(
              'ALTER TABLE security_config ADD COLUMN daily_pdf_exports INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE security_config ADD COLUMN daily_pdf_export_date TEXT',
            );
            // Create audit_logs table
            await customStatement('''
              CREATE TABLE IF NOT EXISTS audit_logs (
                id TEXT NOT NULL PRIMARY KEY,
                teacher_id TEXT,
                school_id TEXT,
                action TEXT NOT NULL,
                metadata TEXT,
                created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
              )
            ''');
          }
          if (from < 14) {
            // Add temp_password column to teachers table for pending teachers
            await customStatement(
              'ALTER TABLE teachers ADD COLUMN temp_password TEXT',
            );
          }
          if (from < 15) {
            // Add status + admin edits to scheme_of_work
            await customStatement(
              "ALTER TABLE scheme_of_work ADD COLUMN teacher_id INTEGER NOT NULL DEFAULT 0",
            );
            await customStatement(
              "ALTER TABLE scheme_of_work ADD COLUMN status TEXT NOT NULL DEFAULT 'draft'",
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN admin_edited_topic TEXT',
            );
            await customStatement(
              'ALTER TABLE scheme_of_work ADD COLUMN admin_comment TEXT',
            );
            // Add status column to lessons
            await customStatement(
              "ALTER TABLE lessons ADD COLUMN status TEXT NOT NULL DEFAULT 'draft'",
            );
            // Expand progress_logs table from stub (id-only) to full schema
            await customStatement(
              'ALTER TABLE progress_logs ADD COLUMN server_id TEXT',
            );
            await customStatement(
              "ALTER TABLE progress_logs ADD COLUMN event_type TEXT NOT NULL DEFAULT ''",
            );
            await customStatement(
              'ALTER TABLE progress_logs ADD COLUMN lesson_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE progress_logs ADD COLUMN teacher_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE progress_logs ADD COLUMN school_id INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              "ALTER TABLE progress_logs ADD COLUMN event_date TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP",
            );
            await customStatement(
              'ALTER TABLE progress_logs ADD COLUMN update_counter INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              'ALTER TABLE progress_logs ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0',
            );
            await customStatement(
              "ALTER TABLE progress_logs ADD COLUMN created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP",
            );
            await customStatement(
              "ALTER TABLE progress_logs ADD COLUMN updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP",
            );
          }
          if (from < 16) {
            final deviceId = const Uuid().v4();
            // Query existing columns to make migration idempotent
            final existingColumns = await customSelect(
              "SELECT name FROM pragma_table_info('security_config')",
            ).get();
            final columnNames =
                existingColumns.map((r) => r.read<String>('name')).toSet();

            if (!columnNames.contains('sync_pending_after_biometric_timeout')) {
              await customStatement(
                "ALTER TABLE security_config ADD COLUMN sync_pending_after_biometric_timeout INTEGER NOT NULL DEFAULT 0",
              );
            }
            if (!columnNames.contains('current_device_id')) {
              await customStatement(
                "ALTER TABLE security_config ADD COLUMN current_device_id TEXT NOT NULL DEFAULT ''",
              );
            }
            if (!columnNames.contains('daily_preview_count')) {
              await customStatement(
                "ALTER TABLE security_config ADD COLUMN daily_preview_count INTEGER NOT NULL DEFAULT 0",
              );
            }
            if (!columnNames.contains('daily_preview_date')) {
              await customStatement(
                "ALTER TABLE security_config ADD COLUMN daily_preview_date TEXT",
              );
            }
            if (!columnNames.contains('pending_db_replacement')) {
              await customStatement(
                "ALTER TABLE security_config ADD COLUMN pending_db_replacement INTEGER NOT NULL DEFAULT 0",
              );
            }
            if (!columnNames.contains('vacuumed_db_path')) {
              await customStatement(
                "ALTER TABLE security_config ADD COLUMN vacuumed_db_path TEXT",
              );
            }
            await customStatement(
              "UPDATE security_config SET current_device_id = '$deviceId' WHERE id = 1",
            );
          }
          if (from < 17) {
            // Backfill columns missing from earlier migrations
            final v17Columns = await customSelect(
              "SELECT name FROM pragma_table_info('conflicts')",
            ).get();
            final v17ColNames =
                v17Columns.map((r) => r.read<String>('name')).toSet();

            if (!v17ColNames.contains('local_value')) {
              await customStatement(
                'ALTER TABLE conflicts ADD COLUMN local_value TEXT NULL',
              );
            }
            if (!v17ColNames.contains('remote_value')) {
              await customStatement(
                'ALTER TABLE conflicts ADD COLUMN remote_value TEXT NULL',
              );
            }

            final lessonCols = await customSelect(
              "SELECT name FROM pragma_table_info('lessons')",
            ).get();
            final lessonColNames =
                lessonCols.map((r) => r.read<String>('name')).toSet();

            if (!lessonColNames.contains('teacher_server_id')) {
              await customStatement(
                'ALTER TABLE lessons ADD COLUMN teacher_server_id TEXT NULL',
              );
            }
            if (!lessonColNames.contains('school_server_id')) {
              await customStatement(
                'ALTER TABLE lessons ADD COLUMN school_server_id TEXT NULL',
              );
            }
            if (!lessonColNames.contains('is_unlocked')) {
              await customStatement(
                'ALTER TABLE lessons ADD COLUMN is_unlocked INTEGER NOT NULL DEFAULT 0',
              );
            }

            final examCols = await customSelect(
              "SELECT name FROM pragma_table_info('exams')",
            ).get();
            final examColNames =
                examCols.map((r) => r.read<String>('name')).toSet();

            if (!examColNames.contains('teacher_server_id')) {
              await customStatement(
                'ALTER TABLE exams ADD COLUMN teacher_server_id TEXT NULL',
              );
            }
            if (!examColNames.contains('school_server_id')) {
              await customStatement(
                'ALTER TABLE exams ADD COLUMN school_server_id TEXT NULL',
              );
            }
            if (!examColNames.contains('is_unlocked')) {
              await customStatement(
                'ALTER TABLE exams ADD COLUMN is_unlocked INTEGER NOT NULL DEFAULT 0',
              );
            }
          }
          if (from < 18) {
            // Add scheme_of_work_id and week_number columns to lessons and exams
            final lessonCols = await customSelect(
              "SELECT name FROM pragma_table_info('lessons')",
            ).get();
            final lessonColNames =
                lessonCols.map((r) => r.read<String>('name')).toSet();
            if (!lessonColNames.contains('scheme_of_work_id')) {
              await customStatement(
                'ALTER TABLE lessons ADD COLUMN scheme_of_work_id TEXT',
              );
            }
            if (!lessonColNames.contains('week_number')) {
              await customStatement(
                'ALTER TABLE lessons ADD COLUMN week_number INTEGER',
              );
            }
            final examCols = await customSelect(
              "SELECT name FROM pragma_table_info('exams')",
            ).get();
            final examColNames =
                examCols.map((r) => r.read<String>('name')).toSet();
            if (!examColNames.contains('scheme_of_work_id')) {
              await customStatement(
                'ALTER TABLE exams ADD COLUMN scheme_of_work_id TEXT',
              );
            }
            if (!examColNames.contains('week_number')) {
              await customStatement(
                'ALTER TABLE exams ADD COLUMN week_number INTEGER',
              );
            }
          }
          if (from < 19) {
            final teacherCols = await customSelect(
              "SELECT name FROM pragma_table_info('teachers')",
            ).get();
            final teacherColNames =
                teacherCols.map((r) => r.read<String>('name')).toSet();

            if (!teacherColNames.contains('last_credit_refill_date')) {
              await customStatement(
                'ALTER TABLE teachers ADD COLUMN last_credit_refill_date INTEGER NULL',
              );
            }
            if (!teacherColNames.contains('salt')) {
              await customStatement(
                'ALTER TABLE teachers ADD COLUMN salt TEXT NULL',
              );
            }
            if (!teacherColNames.contains('last_modified_by')) {
              await customStatement(
                'ALTER TABLE teachers ADD COLUMN last_modified_by TEXT NULL',
              );
            }

            final schoolCols = await customSelect(
              "SELECT name FROM pragma_table_info('schools')",
            ).get();
            final schoolColNames =
                schoolCols.map((r) => r.read<String>('name')).toSet();

            if (!schoolColNames.contains('last_modified_by')) {
              await customStatement(
                'ALTER TABLE schools ADD COLUMN last_modified_by TEXT NULL',
              );
            }
          }
          if (from < 19) {
            final teacherCols = await customSelect(
              "SELECT name FROM pragma_table_info('teachers')",
            ).get();
            final teacherColNames =
                teacherCols.map((r) => r.read<String>('name')).toSet();
            if (!teacherColNames.contains('theme_mode')) {
              await customStatement(
                "ALTER TABLE teachers ADD COLUMN theme_mode TEXT NOT NULL DEFAULT 'system'",
              );
            }
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
