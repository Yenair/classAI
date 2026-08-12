// ⚠️ ONE-TIME MANUAL CLEANUP TOOL — DELETE AFTER USE ⚠️
//
// This file is a throwaway, one-shot execution harness. It is NOT a unit test.
// It is NOT wired into app startup and is NOT tracked in git (do not commit).
//
// PURPOSE
// -------
// On some devices, stale `vault_items` entries accumulated in the local
// `sync_queue` table and jam the sync queue. This script opens the REAL
// encrypted device database (the same `classai.db` path the app uses, opened
// with the SQLCipher passphrase obtained from SecurityService exactly like the
// app does) and deletes every `vault_items` sync-queue entry.
//
// It is idempotent: running it multiple times is safe — the second run simply
// finds nothing to delete and prints 0.
//
// HOW TO RUN
// ----------
//   flutter test test/run_vault_cleanup_once.dart
//
// It prints the number of deleted rows to the console.
//
// !! After the cleanup has been confirmed on the device, DELETE THIS FILE. !!
import 'dart:io';

import 'package:classai/core/database/database.dart';
import 'package:classai/core/services/security_service.dart';
import 'package:classai/core/services/vault_queue_cleanup.dart';

Future<void> main() async {
  stdout.writeln('=== Vault sync-queue cleanup (one-time tool) ===');

  // The default AppDatabase() constructor opens the real encrypted database
  // at getApplicationDocumentsDirectory()/classai.db and obtains the correct
  // SQLCipher passphrase from SecurityService — the exact same connection the
  // app uses (see AppDatabase._openConnection).
  final db = AppDatabase();
  try {
    await db.initialize();
    final deleted = await removeVaultSyncQueueEntries(db);
    stdout.writeln('Deleted $deleted vault_items sync-queue entr(y/ies).');
    stdout.writeln('Cleanup complete. This tool can now be deleted.');
  } finally {
    await db.close();
  }
}
