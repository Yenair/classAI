import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class SecurityService {
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final LocalAuthentication _localAuth = LocalAuthentication();
  static const _lastLoggedInTeacherKey = 'last_logged_in_teacher';

  /// Key under which the SQLCipher database encryption passphrase is stored.
  ///
  /// The passphrase protects the local `classai.db` file at rest. It is
  /// generated once (see [getOrCreateDbEncryptionPassphrase]) and stored in
  /// the platform secure enclave / keystore via [FlutterSecureStorage], the
  /// same mechanism used for the JWT, password hash and session key above.
  ///
  /// NOTE: If this key is ever cleared or invalidated (app data reset, iOS
  /// keychain wipe, Android Keystore invalidation), the encrypted database
  /// becomes unreadable and local-only data is unrecoverable. This risk is
  /// accepted by design for this change.
  static const _dbEncryptionKey = 'db_encryption_key';

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
      // For local_auth 2.3.0, use named params directly
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

  /// Store JWT in secure storage (for auto-login persistence)
  Future<void> storeJwt(String jwt) async {
    await _secureStorage.write(key: 'auth_token', value: jwt);
  }

  /// Read stored JWT from secure storage
  Future<String?> getStoredJwt() async {
    return await _secureStorage.read(key: 'auth_token');
  }

  /// Clear stored JWT from secure storage
  Future<void> clearJwt() async {
    await _secureStorage.delete(key: 'auth_token');
  }

  /// Store the identifier of the teacher who last completed a successful
  /// login on this device.
  Future<void> storeLastLoggedInTeacherIdentifier(String identifier) async {
    await _secureStorage.write(
      key: _lastLoggedInTeacherKey,
      value: identifier,
    );
  }

  /// Read the identifier of the teacher who last completed a successful
  /// login on this device.
  Future<String?> getLastLoggedInTeacherIdentifier() async {
    return await _secureStorage.read(key: _lastLoggedInTeacherKey);
  }

  /// Clear the cached last-login teacher marker from secure storage.
  Future<void> clearLastLoggedInTeacherIdentifier() async {
    await _secureStorage.delete(key: _lastLoggedInTeacherKey);
  }

  /// Clear auth-related credentials (JWT, session key, password hash, cached
  /// last-login marker) but PRESERVE the SQLCipher database encryption
  /// passphrase (`db_encryption_key`).
  ///
  /// The passphrase is a device-scoped data key that must remain stable for as
  /// long as the encrypted `classai.db` file exists on disk. Clearing it on
  /// logout (as a blanket [clearAll] would) while leaving the encrypted file
  /// behind would regenerate a NEW passphrase on the next launch and cause a
  /// SQLCipher HMAC key-mismatch on the stale file. Auth credentials, by
  /// contrast, are per-session and safe to wipe on logout.
  Future<void> clearAuthCredentials() async {
    await _secureStorage.delete(key: 'auth_token');
    await _secureStorage.delete(key: 'session_key');
    await _secureStorage.delete(key: 'session_key_expiry');
    await _secureStorage.delete(key: 'password_hash');
    await _secureStorage.delete(key: _lastLoggedInTeacherKey);
  }

  /// Delete ONLY the SQLCipher database encryption passphrase.
  ///
  /// Used by the key-mismatch recovery flow, AFTER the user explicitly
  /// confirms, so a brand-new passphrase is generated next launch and matches
  /// the freshly-created (or re-initialised) database. This must never be
  /// called in the normal logout path (see [clearAuthCredentials]).
  Future<void> clearDbEncryptionPassphrase() async {
    await _secureStorage.delete(key: _dbEncryptionKey);
  }

  /// Read the stored SQLCipher database encryption passphrase, or `null` if
  /// none has been generated yet.
  ///
  /// This should be called on the main isolate. The passphrase is intentionally
  /// returned to the caller so it can be threaded into background isolates
  /// (e.g. drift's `createInBackground` or the vacuum service) rather than
  /// re-read from secure storage inside those isolates.
  Future<String?> getDbEncryptionPassphrase() async {
    return await _secureStorage.read(key: _dbEncryptionKey);
  }

  /// Return the SQLCipher database encryption passphrase, generating and
  /// persisting it on first call if it does not already exist.
  ///
  /// The passphrase is 32 cryptographically-random bytes, base64-encoded. It is
  /// generated exactly once and never regenerated — regenerating it would make
  /// the existing encrypted database unreadable.
  Future<String> getOrCreateDbEncryptionPassphrase() async {
    final existing = await getDbEncryptionPassphrase();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final random = Random.secure();
    final bytes = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    final passphrase = base64Encode(bytes);

    await _secureStorage.write(key: _dbEncryptionKey, value: passphrase);
    return passphrase;
  }

  /// Clear all sensitive data from secure storage
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }
}
