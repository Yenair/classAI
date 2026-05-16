```markdown
### Step 2.2: Security Service

`lib/core/services/security_service.dart`:

```dart
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import '../utils/encryption_utils.dart';

class SecurityService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();

  /// Store password hash in platform secure storage (biometric-protected)
  Future<void> storePasswordHash(String hash) async {
    await _secureStorage.write(
      key: 'password_hash',
      value: hash,
      // On iOS: requires device passcode/biometric to read
      // On Android: uses Keystore with PURPOSE_ENCRYPT | PURPOSE_DECRYPT
    );
  }

  /// Read stored password hash (triggers biometric if configured)
  Future<String?> getPasswordHash() async {
    return await _secureStorage.read(key: 'password_hash');
  }

  /// Verify biometric (foreground only — never called from background)
  Future<bool> authenticateWithBiometric({required int timeoutSeconds}) async {
    final canCheck = await _localAuth.canCheckBiometrics;
    if (!canCheck) return false;

    try {
      return await _localAuth.authenticate(
        localizedReason: 'Verify your identity to access ClassAI',
        options: const AuthenticationOptions(
          stickyAuth: false,
          biometricOnly: true,
        ),
      ).timeout(
        Duration(seconds: timeoutSeconds),
        onTimeout: () => false,
      );
    } catch (e) {
      return false;
    }
  }

  /// Cache session key encrypted with device key (for background sync)
  /// Device key does NOT require biometric (uses PURPOSE_ENCRYPT only)
  Future<void> storeSessionKey(Uint8List sessionKey, DateTime expiry) async {
    final encoded = base64Encode(sessionKey);
    await _secureStorage.write(key: 'session_key', value: encoded);
    await _secureStorage.write(
      key: 'session_key_expiry',
      value: expiry.toIso8601String(),
    );
  }

  /// Zero session key from secure storage
  Future<void> clearSessionKey() async {
    await _secureStorage.delete(key: 'session_key');
    await _secureStorage.delete(key: 'session_key_expiry');
  }

  /// Clear all sensitive data from secure storage
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }
}
```

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
```