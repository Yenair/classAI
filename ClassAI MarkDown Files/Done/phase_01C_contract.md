```markdown
### Step 1.7: Minimal main.dart

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/database/database.dart';
import 'core/theme/app_theme.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError(
    'databaseProvider must be overridden in main() before use'
  );
});

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Single database instance — initialized once, shared via ProviderScope override
  final db = AppDatabase();
  await db.initialize();

  runApp(
    ProviderScope(
      overrides: [
        databaseProvider.overrideWithValue(db),
      ],
      child: MaterialApp(
        title: 'ClassAI',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const DatabaseStatusScreen(),
      ),
    ),
  );
}

class DatabaseStatusScreen extends StatelessWidget {
  const DatabaseStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ClassAI')),
      body: const Center(child: Text('Database OK')),
    );
  }
}
```

### Step 1.8: Generate Drift Code

```bash
flutter pub run build_runner build --delete-conflicting-outputs
```

## Phase 1 Acceptance Criteria (GATE)

```bash
# Must all pass before Phase 2:
flutter test test/database/schema_test.dart          # All tables created, columns match spec
flutter test test/database/integrity_test.dart       # PRAGMA integrity_check returns 'ok'
flutter test test/database/wal_mode_test.dart        # PRAGMA journal_mode returns 'wal'
flutter test test/database/fts5_test.dart            # FTS5 table created, search works
flutter test test/theme/contrast_test.dart           # Color contrast ratios meet WCAG AAA
flutter build windows --debug                        # Compiles without errors (or macOS/Linux)
```

## Phase 1 Test Files to Create

**`test/database/schema_test.dart`** — For each table, verify it exists and has expected columns:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/database/database.dart';

void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting();
  });

  tearDown(() async {
    await db.close();
  });

  test('all tables created', () async {
    final tables = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
    ).get();
    final names = tables.map((r) => r.read<String>('name')).toList();
    expect(names, contains('schools'));
    expect(names, contains('teachers'));
    expect(names, contains('lessons'));
    expect(names, contains('version_hashes'));
    expect(names, contains('conflicts'));
    expect(names, contains('security_config'));
    // ... all other tables
  });

  test('integrity check passes', () async {
    final result = await db.customSelect('PRAGMA integrity_check').get();
    expect(result.first.read<String>('integrity_check'), 'ok');
  });

  test('WAL mode enabled', () async {
    final result = await db.customSelect('PRAGMA journal_mode').get();
    expect(result.first.read<String>('journal_mode'), 'wal');
  });
}
```

**`test/theme/contrast_test.dart`** — Verify contrast ratios:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/theme/app_theme.dart';

double luminance(Color c) {
  // WCAG relative luminance calculation
  double r = c.red / 255, g = c.green / 255, b = c.blue / 255;
  r = r <= 0.03928 ? r / 12.92 : pow((r + 0.055) / 1.055, 2.4);
  g = g <= 0.03928 ? g / 12.92 : pow((g + 0.055) / 1.055, 2.4);
  b = b <= 0.03928 ? b / 12.92 : pow((b + 0.055) / 1.055, 2.4);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
}

double contrastRatio(Color a, Color b) {
  final l1 = luminance(a), l2 = luminance(b);
  return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05);
}

void main() {
  test('WCAG AAA contrast ratios', () {
    expect(contrastRatio(AppTheme.primary, AppTheme.onPrimary), greaterThanOrEqualTo(7.0));
    expect(contrastRatio(AppTheme.surface, AppTheme.onSurface), greaterThanOrEqualTo(7.0));
    expect(contrastRatio(AppTheme.error, AppTheme.surface), greaterThanOrEqualTo(7.0));
  });
}
```
```