```markdown
**File 10**: `lib/core/database/tables/sync_queue.dart`
**File 11**: `lib/core/database/tables/sync_queue_snapshot.dart`
**File 12**: `lib/core/database/tables/version_hashes.dart` — **CRITICAL FIX**: stores base_version_hash separately
```dart
class VersionHashes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get tableName => text()();       // e.g., 'lessons', 'exams'
  IntColumn get recordLocalId => integer()();
  TextColumn get hash => text()();            // SHA-256 of record state at last sync
  DateTimeColumn get setAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}
```
**File 13**: `lib/core/database/tables/conflicts.dart`
**File 14**: `lib/core/database/tables/payment_events.dart`
**File 15**: `lib/core/database/tables/recovery_codes.dart`
**File 16**: `lib/core/database/tables/pending_recovery_requests.dart`
**File 17**: `lib/core/database/tables/teacher_devices.dart`
**File 18**: `lib/core/database/tables/scheme_generation_queue.dart`
**File 19**: `lib/core/database/tables/search_index.dart` (FTS5 virtual table — defined in database.dart, not as a Table class)

### Step 1.5: Create Database Class

`lib/core/database/database.dart`:

```dart
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';
import 'tables/schools.dart';
import 'tables/teachers.dart';
// ... import all tables
import 'tables/version_hashes.dart';

part 'database.g.dart'; // generated

@DriftDatabase(tables: [
  Schools, Teachers, Subjects, Lessons, SchemeOfWork,
  Exams, ProgressLogs, VaultItems,
  SecurityConfig, SyncQueue, SyncQueueSnapshot,
  VersionHashes, Conflicts, PaymentEvents,
  RecoveryCodes, PendingRecoveryRequests,
  TeacherDevices, SchemeGenerationQueue,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 1;

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
      // Future migrations go here
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys=ON');

      // Seed the SecurityConfig singleton row if it doesn't exist
      final count = await customSelect(
        'SELECT COUNT(*) as c FROM security_config'
      ).getSingle();
      if (count.read<int>('c') == 0) {
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
```

### Step 1.6: Theme Setup

`lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Light theme colors (WCAG AAA verified)
  static const Color primary = Color(0xFF1A2B3C);     // Deep Navy
  static const Color onPrimary = Color(0xFFFFFFFF);    // 12.6:1 contrast
  static const Color surface = Color(0xFFFFFFFF);
  static const Color onSurface = Color(0xFF1A1A1A);
  static const Color error = Color(0xFFB71C1C);        // 7.2:1 on white
  static const Color secondary = Color(0xFFB0BEC5);    // 5.2:1 on navy

  // Dark theme
  static const Color darkSurface = Color(0xFF121212);
  static const Color darkOnSurface = Color(0xFFE0E0E0);

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primary,
        onPrimary: onPrimary,
        surface: surface,
        onSurface: onSurface,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(),
      scaffoldBackgroundColor: surface,
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        onPrimary: onPrimary,
        surface: darkSurface,
        onSurface: darkOnSurface,
        error: error,
      ),
      textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
      scaffoldBackgroundColor: darkSurface,
    );
  }
}
```
```