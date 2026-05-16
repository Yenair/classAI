import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/utils/encryption_utils.dart';
import 'dart:convert';

void main() {
  group('AES-256-GCM', () {
    test('encrypt then decrypt returns original', () async {
      final key = EncryptionUtils.generateKey();
      final plaintext = 'Hello, ClassAI! This is a lesson about photosynthesis.';

      final encrypted = await EncryptionUtils.encryptAesGcm(key, plaintext);
      final decrypted = await EncryptionUtils.decryptAesGcm(key, encrypted);

      expect(decrypted, equals(plaintext));
    });

    test('same plaintext produces different ciphertext (random IV)', () async {
      final key = EncryptionUtils.generateKey();
      final plaintext = 'Same text';

      final e1 = await EncryptionUtils.encryptAesGcm(key, plaintext);
      final e2 = await EncryptionUtils.encryptAesGcm(key, plaintext);

      expect(e1, isNot(equals(e2)));
      expect(await EncryptionUtils.decryptAesGcm(key, e1), equals(plaintext));
      expect(await EncryptionUtils.decryptAesGcm(key, e2), equals(plaintext));
    });

    test('wrong key fails to decrypt', () async {
      final key1 = EncryptionUtils.generateKey();
      final key2 = EncryptionUtils.generateKey();
      final plaintext = 'Secret data';

      final encrypted = await EncryptionUtils.encryptAesGcm(key1, plaintext);

      await expectLater(
        () => EncryptionUtils.decryptAesGcm(key2, encrypted),
        throwsA(isA<Exception>()),
      );
    });

    test('tampered ciphertext fails to decrypt', () async {
      final key = EncryptionUtils.generateKey();
      final plaintext = 'Secret data';
      final encrypted = await EncryptionUtils.encryptAesGcm(key, plaintext);

      // Tamper with ciphertext (change last byte)
      final bytes = base64Decode(encrypted);
      bytes[bytes.length - 1] ^= 0xFF;
      final tampered = base64Encode(bytes);

      await expectLater(
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