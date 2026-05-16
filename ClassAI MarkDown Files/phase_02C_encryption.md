```markdown

### Step 2.3: Credit Service

`lib/core/services/credit_service.dart`:

```dart
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class CreditService {
  final AppDatabase _db;
  final _uuid = const Uuid();

  CreditService(this._db);

  /// Spend credits for content generation. Returns batch ID.
  /// CRITICAL: Batch ID is written to SQLite BEFORE the network call.
  Future<String> spendCredits({
    required int amount,
    required List<String> contentIds,
  }) async {
    final batchId = _uuid.v4();
    final config = await _db.securityConfigDao.get();

    if (config.offlineCredits < amount) {
      throw CreditInsufficientException(
        available: config.offlineCredits,
        required: amount,
      );
    }

    // 1. Write batch ID FIRST (before network call)
    await _db.securityConfigDao.update(
      creditSpentBatchId: batchId,
    );

    // 2. Decrement locally
    await _db.securityConfigDao.updateOfflineCredits(
      config.offlineCredits - amount,
    );

    // 3. Queue for sync
    await _db.syncQueueDao.insertEntry(
      tableName: 'credit_spend',
      recordLocalId: 0, // synthetic
      operation: 'SPEND_CREDITS',
      payload: {
        'batch_id': batchId,
        'amount': amount,
        'content_ids': contentIds,
      },
    );

    return batchId;
  }

  /// Apply server credit state (overwrites local)
  Future<void> applyServerCreditState({
    required int offlineCredits,
    required List<String> spentIds,
    required int serverCounter,
  }) async {
    final config = await _db.securityConfigDao.get();

    // Detect tampering: if server counter < local counter, possible multi-device race
    if (serverCounter < config.creditServerCounter) {
      // Multi-device race or clock issue. Trust server.
      // Log warning but don't block.
    }

    await _db.securityConfigDao.update(
      offlineCredits: offlineCredits,
      creditSpentIdsLocal: spentIds.toString(), // JSON array
      creditServerCounter: serverCounter,
      creditSpentBatchId: null, // clear pending batch
    );
  }
}

class CreditInsufficientException implements Exception {
  final int available;
  final int required;
  CreditInsufficientException({required this.available, required this.required});

  @override
  String toString() => 'Insufficient credits: have $available, need $required';
}
```

### Step 2.4: Encryption Test File

`test/crypto/encryption_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/utils/encryption_utils.dart';
import 'dart:convert';

void main() {
  group('AES-256-GCM', () {
    test('encrypt then decrypt returns original', () {
      final key = EncryptionUtils.generateKey();
      final plaintext = 'Hello, ClassAI! This is a lesson about photosynthesis.';

      final encrypted = EncryptionUtils.encryptAesGcm(key, plaintext);
      final decrypted = EncryptionUtils.decryptAesGcm(key, encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('same plaintext produces different ciphertext (random IV)', () {
      final key = EncryptionUtils.generateKey();
      final plaintext = 'Same text';

      final e1 = EncryptionUtils.encryptAesGcm(key, plaintext);
      final e2 = EncryptionUtils.encryptAesGcm(key, plaintext);

      expect(e1, isNot(equals(e2)));
      expect(EncryptionUtils.decryptAesGcm(key, e1), equals(plaintext));
      expect(EncryptionUtils.decryptAesGcm(key, e2), equals(plaintext));
    });

    test('wrong key fails to decrypt', () {
      final key1 = EncryptionUtils.generateKey();
      final key2 = EncryptionUtils.generateKey();
      final plaintext = 'Secret data';

      final encrypted = EncryptionUtils.encryptAesGcm(key1, plaintext);

      expect(
        () => EncryptionUtils.decryptAesGcm(key2, encrypted),
        throwsA(isA<Exception>()),
      );
    });

    test('tampered ciphertext fails to decrypt', () {
      final key = EncryptionUtils.generateKey();
      final plaintext = 'Secret data';
      final encrypted = EncryptionUtils.encryptAesGcm(key, plaintext);

      // Tamper with ciphertext (change last byte)
      final bytes = base64Decode(encrypted);
      bytes[bytes.length - 1] ^= 0xFF;
      final tampered = base64Encode(bytes);

      expect(
        () => EncryptionUtils.decryptAesGcm(key, tampered),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('SHA-256', () {
    test('deterministic output', () {
      final h1 = EncryptionUtils.sha256Hash('test');
      final h2 = EncryptionUtils.sha256Hash('test');
      expect(h1, equals(h2));
    });

    test('different inputs produce different hashes', () {
      final h1 = EncryptionUtils.sha256Hash('test');
      final h2 = EncryptionUtils.sha256Hash('test2');
      expect(h1, isNot(equals(h2)));
    });
  });

  group('Constant-time comparison', () {
    test('equal strings return true', () {
      expect(EncryptionUtils.constantTimeCompare('abc123', 'abc123'), isTrue);
    });

    test('different strings return false', () {
      expect(EncryptionUtils.constantTimeCompare('abc123', 'abc124'), isFalse);
    });

    test('different lengths return false', () {
      expect(EncryptionUtils.constantTimeCompare('abc', 'abcd'), isFalse);
    });
  });

  group('Key generation', () {
    test('generates 256-bit key', () {
      final key = EncryptionUtils.generateKey();
      expect(key.length, equals(32)); // 256 bits = 32 bytes
    });

    test('two keys are different', () {
      final k1 = EncryptionUtils.generateKey();
      final k2 = EncryptionUtils.generateKey();
      expect(k1, isNot(equals(k2)));
    });
  });
}
```
```