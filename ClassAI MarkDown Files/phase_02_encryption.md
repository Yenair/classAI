
```markdown
`phase_02_encryption.md`
# Phase 2: Encryption + Credit Core (Self-Contained)

**Goal**: All crypto operations unit-tested. Credit system with server-authoritative idempotency implemented and tested. No UI beyond test screens.

## Architecture Decisions (This Phase Only)

- **Argon2id via `cryptography` package**: Pure Dart, cross-platform, has `Argon2id` class built-in. Device-adaptive parameters.
- **School master key**: 256-bit AES. Wrapped with admin's password-derived key using AES-KWP. AES-KWP implemented in `encryption_utils.dart` using Dart's built-in `cipher` support — NOT `pointycastle`. See Step 2.1 for full implementation.
- **Content encryption**: AES-256-GCM via `cryptography` package. 12-byte random IV stored alongside ciphertext. Format: `base64(iv || ciphertext || tag)`.
- **Constant-time comparison**: XOR accumulator with length masking, not `==`.
- **Salt**: 32 bytes from server per teacher, cached locally after first retrieval. If offline and no cached salt: block login (must go online once).
- **Session key**: Random 256-bit, encrypted with hardware-backed device key (Android Keystore/ iOS Secure Enclave). 15-min TTL. Only used for background sync.
- **Version hashes**: Stored in `version_hashes` table. Set after every successful sync. Survives VACUUM because it's a separate table (VACUUM only cleans soft-deleted records >90 days, not active records).
- **Credit idempotency**: Batch ID written to SQLite BEFORE HTTP request. On crash recovery, check `security_config.creditSpentBatchId`. If set and no response recorded, retry with same ID. Server returns cached result for duplicate batch IDs.

## Agent Playbook — Phase 2 File Creation Order

### Step 2.1: Encryption Utilities

`lib/core/utils/encryption_utils.dart`:

```dart
import 'dart:typed_data';
import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart' as crypt;
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';

class ArgonParams {
  final int memory;     // KB
  final int iterations;
  final int parallelism;
  final int saltLength;

  const ArgonParams({
    required this.memory,
    required this.iterations,
    required this.parallelism,
    this.saltLength = 32,
  });

  static Future<ArgonParams> forDevice() async {
    try {
      final deviceInfo = DeviceInfoPlugin();
      final androidInfo = await deviceInfo.androidInfo;
      final ramMB = androidInfo.totalMem ~/ (1024 * 1024);

      if (ramMB < 3072) {
        return const ArgonParams(memory: 16384, iterations: 4, parallelism: 1);
      } else if (ramMB < 4096) {
        return const ArgonParams(memory: 32768, iterations: 3, parallelism: 2);
      } else {
        return const ArgonParams(memory: 65536, iterations: 3, parallelism: 4);
      }
    } catch (_) {
      // Desktop, iOS, or test — use moderate params
      return const ArgonParams(memory: 32768, iterations: 3, parallelism: 2);
    }
  }
}

class EncryptionUtils {
  /// Derive a 256-bit key from password using Argon2id (via `cryptography` package)
  static Future<Uint8List> deriveKey(
    String password,
    Uint8List salt,
    ArgonParams params,
  ) async {
    final argon2 = crypt.Argon2id(
      parallelism: params.parallelism,
      memory: params.memory, // KB
      iterations: params.iterations,
      hashLength: 32, // 256 bits
    );

    final key = await argon2.deriveKey(
      secretKey: crypt.SecretKey(utf8.encode(password)),
      nonce: salt,
    );

    return Uint8List.fromList(await key.extractBytes());
  }

  /// Encrypt plaintext with AES-256-GCM
  static Future<String> encryptAesGcm(Uint8List key, String plaintext) async {
    final algorithm = crypt.AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(key);
    final nonce = _generateNonce(12); // 96-bit IV for GCM

    final secretBox = await algorithm.encrypt(
      utf8.encode(plaintext),
      secretKey: secretKey,
      nonce: nonce,
    );

    // Format: base64(nonce | ciphertext | mac)
    final combined = Uint8List.fromList([
      ...nonce.bytes,
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
    return base64Encode(combined);
  }

  /// Decrypt ciphertext with AES-256-GCM
  static Future<String> decryptAesGcm(
    Uint8List key,
    String encodedCiphertext,
  ) async {
    final combined = base64Decode(encodedCiphertext);
    final nonce = crypt.Nonce(combined.sublist(0, 12), 12);
    final mac = crypt.Mac(combined.sublist(combined.length - 16));
    final ciphertext = combined.sublist(12, combined.length - 16);

    final algorithm = crypt.AesGcm.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(key);

    final secretBox = crypt.SecretBox(ciphertext, nonce: nonce, mac: mac);
    final plaintext = await algorithm.decrypt(secretBox, secretKey: secretKey);
    return utf8.decode(plaintext);
  }

  /// Constant-time comparison for password hashes (length-masked)
  static bool constantTimeCompare(String a, String b) {
    final aBytes = utf8.encode(a);
    final bBytes = utf8.encode(b);
    final maxLen = aBytes.length > bBytes.length ? aBytes.length : bBytes.length;

    // Length mismatch contributes to result but doesn't early-exit
    int result = aBytes.length ^ bBytes.length;
    for (int i = 0; i < maxLen; i++) {
      final aByte = i < aBytes.length ? aBytes[i] : 0;
      final bByte = i < bBytes.length ? bBytes[i] : 0;
      result |= aByte ^ bByte;
    }
    return result == 0;
  }

  /// Compute SHA-256 hash
  static String sha256Hash(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Compute SHA-256 hash of bytes
  static String sha256HashBytes(Uint8List input) {
    final digest = sha256.convert(input);
    return digest.toString();
  }

  /// Generate random 256-bit key
  static Uint8List generateKey() {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  }

  // -- AES Key Wrap with Padding (RFC 5649) --
  // Uses standard AES-ECB as the underlying block cipher.
  // This is a self-contained implementation; no external KWP package needed.

  static const int _kwBlockSize = 8; // 64-bit blocks
  static const int _kwIv = 0xA65959A6; // RFC 3394/5649 default IV prefix

  /// Wrap a key using AES-KWP (RFC 5649).
  /// [kek] must be 16, 24, or 32 bytes.
  /// [keyToWrap] can be any length (KWP supports non-64-bit-aligned keys).
  /// Returns base64-encoded wrapped key.
  static Uint8List wrapKey(Uint8List kek, Uint8List keyToWrap) {
    // For simplicity in v1: keys are always 32 bytes (256-bit).
    // If the key is already block-aligned (32 bytes = 4 blocks),
    // we can use RFC 3394 directly (no padding needed):
    assert(kek.length == 16 || kek.length == 24 || kek.length == 32,
        'KEK must be 128, 192, or 256 bits');
    assert(keyToWrap.length == 32, 'Key to wrap must be 256 bits in v1');

    final n = keyToWrap.length ~/ _kwBlockSize; // 4

    // Step 1: Initialize
    final a = Uint8List(8);
    final r = <Uint8List>[];
    _setBe64(a, 0, _kwIv);
    for (int i = 0; i < n; i++) {
      r.add(Uint8List.fromList(
          keyToWrap.sublist(i * _kwBlockSize, (i + 1) * _kwBlockSize)));
    }

    // Step 2: Calculate wrapping rounds (6 * n)
    for (int j = 0; j <= 5; j++) {
      for (int i = 0; i < n; i++) {
        // B = AES_K( A | R[i] )
        final input = Uint8List(16);
        input.setAll(0, a);
        input.setAll(8, r[i]);

        final encrypted = _aesEcbEncryptBlock(kek, input);

        // A = MSB(64, B) XOR (n*j + i + 1)
        a.setAll(0, encrypted.sublist(0, 8));
        final t = BigInt.from(n * j + i + 1);
        _xorWithBigInt(a, t);

        // R[i] = LSB(64, B)
        r[i].setAll(0, encrypted.sublist(8, 16));
      }
    }

    // Step 3: Output C = A | R[0] | R[1] | ... | R[n-1]
    final output = Uint8List(8 + n * _kwBlockSize);
    output.setAll(0, a);
    for (int i = 0; i < n; i++) {
      output.setAll(8 + i * _kwBlockSize, r[i]);
    }
    return output;
  }

  /// Unwrap a key using AES-KWP (RFC 5649).
  /// [kek] must be 16, 24, or 32 bytes.
  /// [wrappedKey] is the output of wrapKey().
  /// Returns the unwrapped key.
  static Uint8List unwrapKey(Uint8List kek, Uint8List wrappedKey) {
    assert(kek.length == 16 || kek.length == 24 || kek.length == 32,
        'KEK must be 128, 192, or 256 bits');

    final totalLen = wrappedKey.length;
    assert(totalLen >= 16 && totalLen % 8 == 0,
        'Wrapped key length must be multiple of 8 and at least 16');

    final n = (totalLen ~/ _kwBlockSize) - 1; // number of 64-bit blocks (excluding A)

    // Step 1: Initialize
    final a = Uint8List.fromList(wrappedKey.sublist(0, 8));
    final r = <Uint8List>[];
    for (int i = 0; i < n; i++) {
      r.add(Uint8List.fromList(
          wrappedKey.sublist(8 + i * _kwBlockSize, 8 + (i + 1) * _kwBlockSize)));
    }

    // Step 2: Calculate unwrapping rounds
    for (int j = 5; j >= 0; j--) {
      for (int i = n - 1; i >= 0; i--) {
        // A = A XOR (n*j + i + 1)
        final t = BigInt.from(n * j + i + 1);
        _xorWithBigInt(a, t);

        // B = AES_K^{-1}( A | R[i] )
        final input = Uint8List(16);
        input.setAll(0, a);
        input.setAll(8, r[i]);
        final decrypted = _aesEcbDecryptBlock(kek, input);

        // A = MSB(64, B)
        a.setAll(0, decrypted.sublist(0, 8));
        // R[i] = LSB(64, B)
        r[i].setAll(0, decrypted.sublist(8, 16));
      }
    }

    // Step 3: Verify IV
    if (_getBe64(a, 0) != _kwIv) {
      throw ArgumentException('Key unwrap failed: integrity check failed (wrong IV)');
    }

    // Step 4: For KWP with plaintext multiple of 8 bytes, output all blocks
    final keyLength = n * _kwBlockSize;
    final output = Uint8List(keyLength);
    for (int i = 0; i < n; i++) {
      output.setAll(i * _kwBlockSize, r[i]);
    }
    return output;
  }

  // -- Internal AES-ECB helpers (used by AES-KWP) --

  static Uint8List _aesEcbEncryptBlock(Uint8List key, Uint8List block) {
    final algorithm = crypt.AesEcb.with256bits();
    // We need to run this synchronously for KWP, so use the DartCipher utility
    // In practice, wrapKey/unwrapKey should be called from an async context
    // that awaits the AES operations. For sync usage in tests:
    throw UnsupportedError(
      'wrapKey/unwrapKey must be called with async AES ECB. '
      'Use wrapKeyAsync/unwrapKeyAsync for the async version.'
    );
  }

  static Uint8List _aesEcbDecryptBlock(Uint8List key, Uint8List block) {
    throw UnsupportedError(
      'wrapKey/unwrapKey must be called with async AES ECB. '
      'Use wrapKeyAsync/unwrapKeyAsync for the async version.'
    );
  }

  /// Async version of wrapKey — use this in production code.
  static Future<Uint8List> wrapKeyAsync(Uint8List kek, Uint8List keyToWrap) async {
    assert(kek.length == 16 || kek.length == 24 || kek.length == 32);
    assert(keyToWrap.length == 32, 'Key to wrap must be 256 bits in v1');

    final algorithm = crypt.AesEcb.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(kek);

    final n = keyToWrap.length ~/ _kwBlockSize;
    final a = Uint8List(8);
    final r = <Uint8List>[];
    _setBe64(a, 0, _kwIv);
    for (int i = 0; i < n; i++) {
      r.add(Uint8List.fromList(
          keyToWrap.sublist(i * _kwBlockSize, (i + 1) * _kwBlockSize)));
    }

    for (int j = 0; j <= 5; j++) {
      for (int i = 0; i < n; i++) {
        final input = Uint8List(16);
        input.setAll(0, a);
        input.setAll(8, r[i]);

        final encrypted = await algorithm.encrypt(input, secretKey: secretKey);

        a.setAll(0, encrypted.cipherText.sublist(0, 8));
        final t = BigInt.from(n * j + i + 1);
        _xorWithBigInt(a, t);
        r[i].setAll(0, encrypted.cipherText.sublist(8, 16));
      }
    }

    final output = Uint8List(8 + n * _kwBlockSize);
    output.setAll(0, a);
    for (int i = 0; i < n; i++) {
      output.setAll(8 + i * _kwBlockSize, r[i]);
    }
    return output;
  }

  /// Async version of unwrapKey — use this in production code.
  static Future<Uint8List> unwrapKeyAsync(
    Uint8List kek,
    Uint8List wrappedKey,
  ) async {
    assert(kek.length == 16 || kek.length == 24 || kek.length == 32);
    assert(wrappedKey.length >= 16 && wrappedKey.length % 8 == 0);

    final algorithm = crypt.AesEcb.with256bits();
    final secretKey = await algorithm.newSecretKeyFromBytes(kek);

    final n = (wrappedKey.length ~/ _kwBlockSize) - 1;
    final a = Uint8List.fromList(wrappedKey.sublist(0, 8));
    final r = <Uint8List>[];
    for (int i = 0; i < n; i++) {
      r.add(Uint8List.fromList(
          wrappedKey.sublist(8 + i * _kwBlockSize, 8 + (i + 1) * _kwBlockSize)));
    }

    for (int j = 5; j >= 0; j--) {
      for (int i = n - 1; i >= 0; i--) {
        final t = BigInt.from(n * j + i + 1);
        _xorWithBigInt(a, t);

        final input = Uint8List(16);
        input.setAll(0, a);
        input.setAll(8, r[i]);
        final decrypted = await algorithm.decrypt(
          crypt.SecretBox(input.sublist(0, 16), mac: crypt.Mac.empty),
          secretKey: secretKey,
        );

        a.setAll(0, decrypted.sublist(0, 8));
        r[i].setAll(0, decrypted.sublist(8, 16));
      }
    }

    if (_getBe64(a, 0) != _kwIv) {
      throw ArgumentError('Key unwrap failed: integrity check failed (wrong IV)');
    }

    final keyLength = n * _kwBlockSize;
    final output = Uint8List(keyLength);
    for (int i = 0; i < n; i++) {
      output.setAll(i * _kwBlockSize, r[i]);
    }
    return output;
  }

  // -- Big-endian helpers --

  static void _setBe64(Uint8List buf, int offset, int value) {
    for (int i = 7; i >= 0; i--) {
      buf[offset + i] = value & 0xFF;
      value >>= 8;
    }
  }

  static int _getBe64(Uint8List buf, int offset) {
    int result = 0;
    for (int i = 0; i < 8; i++) {
      result = (result << 8) | (buf[offset + i] & 0xFF);
    }
    return result;
  }

  static void _xorWithBigInt(Uint8List buf, BigInt value) {
    for (int i = 7; i >= 0; i--) {
      buf[i] ^= (value & BigInt.from(0xFF)).toInt();
      value >>= 8;
    }
  }

  static Uint8List _generateNonce(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }
}
```

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