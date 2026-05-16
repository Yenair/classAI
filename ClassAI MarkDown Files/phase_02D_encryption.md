```markdown
### Step 2.5: Credit Test File

`test/credits/credit_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/credit_service.dart';

void main() {
  late AppDatabase db;
  late CreditService creditService;

  setUp(() async {
    db = AppDatabase();
    await db.initialize();
    creditService = CreditService(db);
    // Set initial credits
    await db.securityConfigDao.update(offlineCredits: 10);
  });

  tearDown(() async {
    await db.close();
  });

  test('spend credits decrements locally', () async {
    final batchId = await creditService.spendCredits(
      amount: 2,
      contentIds: ['content_1', 'content_2'],
    );

    final config = await db.securityConfigDao.get();
    expect(config.offlineCredits, equals(8));
    expect(config.creditSpentBatchId, equals(batchId));
  });

  test('spend credits when insufficient throws', () async {
    expect(
      () => creditService.spendCredits(amount: 20, contentIds: ['x']),
      throwsA(isA<CreditInsufficientException>()),
    );
  });

  test('batch ID is persisted before spend', () async {
    final batchId = await creditService.spendCredits(
      amount: 1,
      contentIds: ['c1'],
    );

    // Verify batch ID is in SQLite
    final config = await db.securityConfigDao.get();
    expect(config.creditSpentBatchId, isNotNull);
    expect(config.creditSpentBatchId, equals(batchId));
  });

  test('server state overwrites local state', () async {
    // Spend some credits locally
    await creditService.spendCredits(amount: 3, contentIds: ['a', 'b', 'c']);

    // Server returns authoritative state
    await creditService.applyServerCreditState(
      offlineCredits: 5,
      spentIds: ['x', 'y'],
      serverCounter: 5,
    );

    final config = await db.securityConfigDao.get();
    expect(config.offlineCredits, equals(5));
    expect(config.creditServerCounter, equals(5));
    expect(config.creditSpentBatchId, isNull); // cleared after sync
  });
}
```

## Phase 2 Acceptance Criteria (GATE)

```bash
flutter test test/crypto/encryption_test.dart          # All crypto tests pass
flutter test test/credits/credit_service_test.dart      # All credit tests pass
flutter test test/crypto/argon2id_device_params_test.dart # Device-adaptive params correct
```
```