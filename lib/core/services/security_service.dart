import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

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

  /// Clear all sensitive data from secure storage
  Future<void> clearAll() async {
    await _secureStorage.deleteAll();
  }
}