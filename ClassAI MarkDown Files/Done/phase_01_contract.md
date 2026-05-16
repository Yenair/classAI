
```markdown
`phase_01_database.md`
# Phase 1: Project Skeleton + Database Core (Self-Contained)

**Goal**: Flutter project compiles. SQLite database opens in WAL mode. All tables created. Integrity check passes. Theme applied. Tests pass.

## Architecture Decisions (This Phase Only)

- WAL mode + foreign keys ON at database open.
- Timestamps use Drift `DateTimeColumn` — Drift handles SQLite storage as Unix epoch integers internally.
- `version_hashes` table stores merge base hashes separately to survive VACUUM.
- No encryption, no sync, no UI beyond a "Database OK" screen.

## Agent Playbook — Phase 1 File Creation Order

### Step 1.1: Create Flutter Project

```bash
flutter create classai --platforms=android,ios,windows,macos,linux
cd classai
```

Replace `pubspec.yaml` with the exact versions listed above. Run `flutter pub get`.

**Verify**: `flutter pub get` exits 0. No version conflicts.

### Step 1.2: Create Directory Structure

```
lib/
├── core/
│   ├── constants/
│   ├── theme/
│   ├── database/
│   │   └── tables/
│   └── utils/
├── features/
│   ├── auth/
│   ├── dashboard/
│   ├── lesson/
│   ├── exam/
│   ├── admin/
│   ├── vault/
│   ├── settings/
│   └── payment/
├── models/
├── router/
└── main.dart
```

Create all directories. Agent creates `lib/core/constants/app_constants.dart` with:

```dart
class AppConstants {
  static const String appName = 'ClassAI';
  static const String deepLinkScheme = 'classai';
  static const int minTabletWidth = 600; // shortestSide for Editor mode
  static const int maxImageSizeKB = 50;
  static const int syncBatchSize = 10;
  static const int maxPushRetries = 5;
  static const Duration pushRetryBase = Duration(seconds: 5);
  static const Duration syncCooldown = Duration(seconds: 60);
  static const Duration sessionKeyTTL = Duration(minutes: 15);
  static const int biometricTimeoutSeconds = 10;
}
```

### Step 1.3: Define Curriculum Constants

`lib/core/constants/curriculum_types.dart`:

```dart
enum CurriculumType { nerdc, cambridge, ccss }

extension CurriculumTypeX on CurriculumType {
  String get code {
    switch (this) {
      case CurriculumType.nerdc: return 'nerdc';
      case CurriculumType.cambridge: return 'cambridge';
      case CurriculumType.ccss: return 'ccss';
    }
  }
  String get displayName {
    switch (this) {
      case CurriculumType.nerdc: return 'NERDC (Nigeria)';
      case CurriculumType.cambridge: return 'Cambridge International';
      case CurriculumType.ccss: return 'CCSS (US Common Core)';
    }
  }
  String get latestVersion {
    switch (this) {
      case CurriculumType.nerdc: return 'nerdc_v2024';
      case CurriculumType.cambridge: return 'cambridge_v2025';
      case CurriculumType.ccss: return 'ccss_v2024';
    }
  }
}

enum SubscriptionTier { free, basic, standard, elite }

extension SubscriptionTierX on SubscriptionTier {
  int get offlineCredits {
    switch (this) {
      case SubscriptionTier.free: return 3;
      case SubscriptionTier.basic: return 5;
      case SubscriptionTier.standard: return 10;
      case SubscriptionTier.elite: return 20;
    }
  }
}
```

### Step 1.4: Define All Drift Tables

Create each table file in `lib/core/database/tables/`. **Order matters** — tables with FK references come after referenced tables.

**File 1**: `lib/core/database/tables/schools.dart`
```dart
import 'package:drift/drift.dart';

class Schools extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()(); // UUID from server
  TextColumn get schoolName => text()();
  TextColumn get shortCode => text()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get subscriptionTier => text().withDefault(const Constant('free'))();
  TextColumn get activeCurriculum => text().withDefault(const Constant('nerdc'))();
  TextColumn get activeCurriculumVersion => text().nullable()();
  IntColumn get totalSeats => integer().withDefault(const Constant(5))();
  TextColumn get schoolMasterKeyWrapped => text().nullable()(); // base64
  TextColumn get adminRecoveryEmail => text().nullable()();
  BoolColumn get adminRecoveryEmailVerified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get lastModifiedBy => text().nullable()(); // teacher_id for sync

  @override
  Set<Column> get primaryKey => {localId};
}
```

**File 2**: `lib/core/database/tables/teachers.dart`
```dart
class Teachers extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  TextColumn get email => text()();
  TextColumn get teacherName => text()();
  TextColumn get role => text().withDefault(const Constant('teacher'))(); // 'teacher' or 'admin'
  IntColumn get schoolLocalId => integer().references(Schools, #localId)();
  TextColumn get schoolServerId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get forcePasswordReset => boolean().withDefault(const Constant(false))();
  IntColumn get passwordHashVersion => integer().withDefault(const Constant(1))();
  TextColumn get schoolKeyWrapped => text().nullable()(); // base64, teacher's wrapped school key
  DateTimeColumn get lastCreditRefillDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get lastModifiedBy => text().nullable()();

  @override
  Set<Column> get primaryKey => {localId};
}
```

**File 3**: `lib/core/database/tables/subjects.dart`
**File 4**: `lib/core/database/tables/lessons.dart` (includes `lockedByTeacherId`, `lockedUntil`, `lockHeartbeat`, `contentHash`)
**File 5**: `lib/core/database/tables/scheme_of_work.dart`
**File 6**: `lib/core/database/tables/exams.dart`
**File 7**: `lib/core/database/tables/progress_logs.dart`
**File 8**: `lib/core/database/tables/vault_items.dart` (includes `minTier`, `contentHash`, `creditsSpent`)
**File 9**: `lib/core/database/tables/security_config.dart` — singleton table
```dart
class SecurityConfig extends Table {
  IntColumn get id => integer().autoIncrement()();
  BoolColumn get isLocked => boolean().withDefault(const Constant(false))();
  DateTimeColumn get lastSeenTime => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastKnownGoodTime => dateTime().nullable()();
  RealColumn get monotonicLastSeen => real().nullable()();

  // Credit state
  IntColumn get offlineCredits => integer().withDefault(const Constant(3))();
  TextColumn get creditSpentIdsLocal => text().withDefault(const Constant('[]'))(); // JSON array
  IntColumn get creditServerCounter => integer().withDefault(const Constant(0))();
  TextColumn get creditSpentBatchId => text().nullable()();
  DateTimeColumn get lastCreditRefillServerTime => dateTime().nullable()();

  // Sync metadata
  DateTimeColumn get lastPullTimestamp => dateTime().nullable()();
  TextColumn get syncCursor => text().nullable()();
  DateTimeColumn get lastSyncAttemptTime => dateTime().nullable()();
  DateTimeColumn get syncCooldownUntil => dateTime().nullable()();

  // Security
  DateTimeColumn get heartbeatLastSuccess => dateTime().nullable()();
  DateTimeColumn get lastVacuumDate => dateTime().nullable()();
  TextColumn get encryptionKeyWrapped => text().nullable()();
  BoolColumn get encryptionRecoveryNeeded => boolean().withDefault(const Constant(false))();
  TextColumn get corruptedRecordIds => text().withDefault(const Constant('[]'))();
  IntColumn get lastKnownPasswordHashVersion => integer().withDefault(const Constant(1))();

  // Session key for background sync
  TextColumn get sessionKeyEncrypted => text().nullable()();
  DateTimeColumn get sessionKeyExpiry => dateTime().nullable()();
  BoolColumn get syncPendingAfterBiometricTimeout => boolean().withDefault(const Constant(false))();

  // Device identity
  TextColumn get currentDeviceId => text()();

  // VACUUM
  BoolColumn get pendingDbReplacement => boolean().withDefault(const Constant(false))();
  TextColumn get vacuumedDbPath => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```
```