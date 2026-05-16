
```markdown
`phase_08_polish.md`
# Phase 8: Polish, Performance, Nigerian Adaptation, Launch Prep

**Goal**: SMS OTP fallback, USSD recovery concept, NGN localization, term/academic calendar, VACUUM (safe version), Sentry monitoring, performance testing, 5-school beta.

## Key Nigerian-Specific Additions (New in V9.0)

1. **SMS OTP via Termii/BulkSMS Nigeria** — alternative to email OTP for activation and recovery.
2. **USSD recovery concept** — documentation + API endpoint for future USSD integration.
3. **NGN currency formatting** — Paystack integration uses Naira (₦) throughout.
4. **Term management** — NERDC trimesters: First Term (Sept-Dec), Second Term (Jan-April), Third Term (April-July). Schema: `terms` table with `start_date`, `end_date`, `name`.
5. **2G/3G optimization** — Image progressive loading, thumbnail caching, sync payload compression.
6. **Low storage alert** — Monitor disk space; alert at <500MB; block PDF generation at <100MB.
7. **Academic calendar integration** — Week numbering aware of term context.

## VACUUM — Fixed V9.0 Approach

```dart
Future<void> safeVacuum() async {
  // 1. Checkpoint WAL to consolidate all data into .db file
  await db.customStatement('PRAGMA wal_checkpoint(TRUNCATE)');

  // 2. Verify checkpoint completed (busy = 0)
  final checkpointResult = await db.customSelect('PRAGMA wal_checkpoint').get();
  final busy = checkpointResult.first.read<int>('busy');
  if (busy > 0) {
    // WAL still has pending data, abort VACUUM, retry after next sync
    return;
  }

  // 3. Copy .db file (WAL is now empty, safe to just copy .db)
  final originalPath = await getDatabasePath();
  final tempPath = '${originalPath}_vacuum';
  File(originalPath).copySync(tempPath);

  // 4. Run VACUUM in background isolate on the temp copy
  final success = await Isolate.run(() async {
    final vacDb = sqlite3.open(tempPath);
    vacDb.execute('VACUUM');
    vacDb.execute('PRAGMA integrity_check');
    vacDb.dispose();
    return true;
  });

  if (success) {
    // 5. Schedule replacement on next cold start
    await securityConfigDao.update(
      pendingDbReplacement: true,
      vacuumedDbPath: tempPath,
      lastVacuumDate: DateTime.now(),
    );
  }
}
```

## Phase 8 Acceptance Criteria (GATE)

```bash
flutter test test/performance/1000_lesson_sync_test.dart
flutter test test/nigerian/sms_otp_test.dart
flutter test test/nigerian/term_calendar_test.dart
flutter test test/vacuum/safe_vacuum_test.dart
flutter test test/storage/low_disk_test.dart
```
```