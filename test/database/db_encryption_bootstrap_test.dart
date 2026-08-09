import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/open.dart';
import 'package:sqlite3/sqlite3.dart' as sql;

import 'package:classai/core/database/database_encryption_bootstrap.dart';
import 'package:classai/core/services/security_service.dart';

/// In-memory fake for `flutter_secure_storage` so tests can run without a real
/// platform channel. Tracks the passphrase key so we can assert it is only
/// generated once.
class FakeSecureStorage extends FlutterSecureStoragePlatform {
  final Map<String, String> store = {};

  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {
    store[key] = value;
  }

  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) async {
    return store[key];
  }

  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) async {
    return store.containsKey(key);
  }

  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {
    store.remove(key);
  }

  @override
  Future<Map<String, String>> readAll({
    required Map<String, String> options,
  }) async {
    return Map.of(store);
  }

  @override
  Future<void> deleteAll({required Map<String, String> options}) async {
    store.clear();
  }
}

/// Windows SQLCipher override mirroring scripts/sqlcipher_manual_copy_probe.dart.
/// Points sqlite3 at the real SQLCipher-enabled DLL so ensureEncrypted
/// genuinely encrypts/decrypts during these tests.
const String kCipherDll =
    r'C:\Users\Yene\classai\build\windows\x64\runner\Debug\sqlite3.dll';

DynamicLibrary _openCipherDll() => DynamicLibrary.open(kCipherDll);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  FlutterSecureStoragePlatform.instance = FakeSecureStorage();

  // Point sqlite3 at the real SQLCipher DLL on Windows before any
  // ensureEncrypted call (mirrors scripts/sqlcipher_manual_copy_probe.dart).
  open.overrideFor(OperatingSystem.windows, _openCipherDll);

  late Directory tempDir;
  late FakeSecureStorage secureStorage;
  late SecurityService security;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('classai_enc_');
    secureStorage = FakeSecureStorage();
    FlutterSecureStoragePlatform.instance = secureStorage;
    security = SecurityService();
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  String dbPath(String name) => p_join(tempDir.path, name);

  /// Helper: create a plaintext SQLite DB with a few rows in each key table.
  void createPlaintextDb(String path, {int vaultRows = 3, int lessonRows = 2}) {
    final db = sql.sqlite3.open(path);
    try {
      db.execute('''
        CREATE TABLE vault_items (id INTEGER PRIMARY KEY AUTOINCREMENT, payload TEXT NOT NULL);
      ''');
      db.execute('''
        CREATE TABLE sync_queue (id INTEGER PRIMARY KEY AUTOINCREMENT, data TEXT NOT NULL);
      ''');
      db.execute('''
        CREATE TABLE lessons (id INTEGER PRIMARY KEY AUTOINCREMENT, title TEXT NOT NULL);
      ''');
      db.execute('''
        CREATE TABLE exams (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL);
      ''');
      for (var i = 0; i < vaultRows; i++) {
        db.execute(
            "INSERT INTO vault_items (payload) VALUES ('v$i');");
      }
      for (var i = 0; i < lessonRows; i++) {
        db.execute("INSERT INTO lessons (title) VALUES ('lesson$i');");
      }
      db.execute('PRAGMA user_version = 24;');
    } finally {
      db.dispose();
    }
  }

  group('DatabaseEncryptionBootstrap.ensureEncrypted', () {
    test('converts a plaintext database to encrypted and keeps a backup',
        () async {
      final plainPath = dbPath('classai.db');
      createPlaintextDb(plainPath, vaultRows: 3, lessonRows: 2);

      final bootstrap = DatabaseEncryptionBootstrap(security);
      final passphrase = await bootstrap.ensureEncrypted(tempDir.path);

      // 1. Passphrase was generated exactly once and persisted.
      expect(passphrase, isNotEmpty);
      final stored =
          await security.getDbEncryptionPassphrase();
      expect(stored, equals(passphrase));

      // 2. The canonical file now requires a key to open (it is encrypted).
      //    Opening without the key must throw.
      final rawOpen = sql.sqlite3.open(plainPath);
      expect(
        () => rawOpen.select('SELECT * FROM vault_items'),
        throwsA(isA<sql.SqliteException>()),
      );
      rawOpen.dispose();

      // 3. Opening with the key succeeds and the data is intact.
      final encrypted = sql.sqlite3.open(plainPath);
      try {
        encrypted.execute("PRAGMA key = '$passphrase';");
        final vaultCount = encrypted
            .select('SELECT COUNT(*) AS c FROM vault_items')
            .first[0];
        final lessonCount = encrypted
            .select('SELECT COUNT(*) AS c FROM lessons')
            .first[0];
        expect(vaultCount, 3);
        expect(lessonCount, 2);

        // user_version preserved so drift does not re-migrate from scratch.
        final userVersion =
            encrypted.select('PRAGMA user_version').first[0];
        expect(userVersion, 24);

        // SQLCipher is genuinely active.
        final cipherVersion =
            encrypted.select('PRAGMA cipher_version').first[0];
        expect('$cipherVersion', isNotEmpty);
      } finally {
        encrypted.dispose();
      }

      // 4. The original plaintext is kept as a dated backup.
      final backups =
          tempDir.listSync().where((e) {
              final name = p_basename(e.path);
              return name.startsWith('classai_preencryption_backup_') &&
                  name.endsWith('.db');
            }).toList();
      expect(backups, hasLength(1));
      // Backup is still plaintext and readable.
      final backupDb = sql.sqlite3.open(backups.first.path);
      try {
        final backupCount = backupDb
            .select('SELECT COUNT(*) AS c FROM vault_items')
            .first[0];
        expect(backupCount, 3);
      } finally {
        backupDb.dispose();
      }

      // 5. Marker is set to complete.
      final state = File(p_join(tempDir.path, 'classai_encryption_state'))
          .readAsStringSync()
          .trim();
      expect(state, 'complete');
    });

    test('is idempotent: second run does not re-convert or rotate the key',
        () async {
      final plainPath = dbPath('classai.db');
      createPlaintextDb(plainPath);

      final bootstrap = DatabaseEncryptionBootstrap(security);
      final first = await bootstrap.ensureEncrypted(tempDir.path);

      // Confirm the DB is now encrypted (no plaintext file at canonical path).
      final backupsAfterFirst = tempDir
          .listSync()
          .where((e) => p_basename(e.path).startsWith('classai_preencryption_'));
      expect(backupsAfterFirst, hasLength(1));

      final second = await bootstrap.ensureEncrypted(tempDir.path);

      // Key must be unchanged (never regenerated).
      expect(second, equals(first));

      // No second backup was created.
      final backupsAfterSecond = tempDir
          .listSync()
          .where((e) => p_basename(e.path).startsWith('classai_preencryption_'));
      expect(backupsAfterSecond, hasLength(1));

      // Canonical file still opens with the key and data intact.
      final encrypted = sql.sqlite3.open(plainPath);
      try {
        encrypted.execute("PRAGMA key = '$first';");
        final count = encrypted
            .select('SELECT COUNT(*) AS c FROM vault_items')
            .first[0];
        expect(count, 3);
      } finally {
        encrypted.dispose();
      }
    });

    test('is a no-op when no database file exists (fresh install)', () async {
      final bootstrap = DatabaseEncryptionBootstrap(security);
      final passphrase = await bootstrap.ensureEncrypted(tempDir.path);

      // A passphrase is still generated for future use, but no conversion
      // happened and no backup file was created.
      expect(passphrase, isNotEmpty);
      expect(File(dbPath('classai.db')).existsSync(), isFalse);
      final backups = tempDir
          .listSync()
          .where((e) => p_basename(e.path).startsWith('classai_preencryption_'));
      expect(backups, isEmpty);
    });

    test('recovers an interrupted conversion (converting marker, temp exists)',
        () async {
      final plainPath = dbPath('classai.db');
      createPlaintextDb(plainPath);

      // Simulate: conversion had already produced and verified the encrypted
      // temp file, but the process was killed before the swap renames. The
      // plaintext is still at the canonical path and the marker is "converting".
      final bootstrap = DatabaseEncryptionBootstrap(security);
      await bootstrap.ensureEncrypted(tempDir.path);
      final passphrase = await security.getDbEncryptionPassphrase();

      // At this point the canonical file is encrypted and marker is "complete".
      // To model a crash during swap, restore a "converting" marker and place an
      // encrypted temp + rename the canonical away, as the real crash window
      // would. Simpler: clear canonical, keep an encrypted temp copy, set
      // marker to converting, and keep the backup (still present).
      final canonical = File(plainPath);
      // Keep a copy of the encrypted canonical as the "temp".
      final tempFile = File(p_join(tempDir.path, 'classai_encrypted.db'));
      canonical.copySync(tempFile.path);
      // Rename the plaintext backup away is unnecessary; just remove canonical
      // to simulate the window where classai.db is temporarily missing.
      canonical.deleteSync();

      File(p_join(tempDir.path, 'classai_encryption_state'))
          .writeAsStringSync('converting');

      final recovery = DatabaseEncryptionBootstrap(security);
      final result = await recovery.ensureEncrypted(tempDir.path);

      expect(result, equals(passphrase));
      // The temp was restored to the canonical path.
      expect(File(plainPath).existsSync(), isTrue);
      final restored = sql.sqlite3.open(plainPath);
      try {
        restored.execute("PRAGMA key = '$passphrase';");
        final count = restored
            .select('SELECT COUNT(*) AS c FROM vault_items')
            .first[0];
        expect(count, 3);
      } finally {
        restored.dispose();
      }
      // Marker is complete.
      final state = File(p_join(tempDir.path, 'classai_encryption_state'))
          .readAsStringSync()
          .trim();
      expect(state, 'complete');
    });

    test('recovers when the swap completed but the marker write was interrupted',
        () async {
      final plainPath = dbPath('classai.db');
      createPlaintextDb(plainPath);

      final bootstrap = DatabaseEncryptionBootstrap(security);
      await bootstrap.ensureEncrypted(tempDir.path);
      final passphrase = await security.getDbEncryptionPassphrase();

      // Simulate: the swap completed (canonical is encrypted) but the "complete"
      // marker was never written. Marker stays "converting".
      File(p_join(tempDir.path, 'classai_encryption_state'))
          .writeAsStringSync('converting');

      final recovery = DatabaseEncryptionBootstrap(security);
      final result = await recovery.ensureEncrypted(tempDir.path);

      expect(result, equals(passphrase));
      // Canonical untouched and encrypted; no second backup created.
      final backups = tempDir
          .listSync()
          .where((e) => p_basename(e.path).startsWith('classai_preencryption_'));
      expect(backups, hasLength(1));
      final state = File(p_join(tempDir.path, 'classai_encryption_state'))
          .readAsStringSync()
          .trim();
      expect(state, 'complete');
    });
  });
}

String p_join(String a, String b) {
  if (a.endsWith('/') || a.endsWith('\\')) return '$a$b';
  return '$a${Platform.pathSeparator}$b';
}

String p_basename(String path) => path.split(Platform.pathSeparator).last;
