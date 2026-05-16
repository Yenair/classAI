```markdown
### Step 7.5: Export Service (`lib/core/services/export_service.dart`)

```dart
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../database/database.dart';

class ExportService {
  final AppDatabase _db;

  ExportService(this._db);

  /// Export all lessons for a subject as CSV
  Future<File> exportLessonsAsCsv(int subjectId) async {
    final lessons = await _db.lessonsDao.getBySubject(subjectId);
    final buffer = StringBuffer();

    // CSV header
    buffer.writeln('Title,Week,Topic,Objectives,Materials,Assessment,Created');

    for (final lesson in lessons) {
      final row = [
        _escapeCsv(lesson.title),
        lesson.weekNumber.toString(),
        _escapeCsv(lesson.topic),
        _escapeCsv(lesson.objectives ?? ''),
        _escapeCsv(lesson.materials ?? ''),
        _escapeCsv(lesson.assessment ?? ''),
        lesson.createdAt.toIso8601String(),
      ];
      buffer.writeln(row.join(','));
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/lessons_export_${DateTime.now().millisecondsSinceEpoch}.csv');
    await file.writeAsString(buffer.toString());
    return file;
  }

  /// Export all school data as JSON (for inspection/accreditation)
  Future<File> exportAllAsJson() async {
    final data = {
      'school': await _db.schoolsDao.get(),
      'teachers': await _db.teachersDao.getAll(),
      'subjects': await _db.subjectsDao.getAll(),
      'lessons': await _db.lessonsDao.getAll(),
      'exams': await _db.examsDao.getAll(),
      'progress_logs': await _db.progressLogsDao.getAll(),
      'exported_at': DateTime.now().toIso8601String(),
    };

    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/classai_export_${DateTime.now().millisecondsSinceEpoch}.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data));
    return file;
  }

  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }
}
```

### Step 7.6: Bulk Operations (`lib/core/services/bulk_operations_service.dart`)

```dart
import '../database/database.dart';

class BulkOperationsService {
  final AppDatabase _db;

  BulkOperationsService(this._db);

  /// Assign one subject to multiple teachers
  Future<void> bulkAssignSubject({
    required int subjectId,
    required List<int> teacherIds,
  }) async {
    await _db.transaction(() async {
      for (final teacherId in teacherIds) {
        await _db.teacherSubjectsDao.insert(
          teacherId: teacherId,
          subjectId: subjectId,
        );
      }
    });
  }

  /// Generate recovery codes for multiple teachers
  /// Requires online connection to server
  Future<Map<int, String>> bulkGenerateRecoveryCodes({
    required int adminId,
    required List<int> teacherIds,
  }) async {
    final results = <int, String>{};
    for (final teacherId in teacherIds) {
      try {
        final code = await _authService.generateTeacherRecoveryCode(
          adminId.toString(),
          teacherId.toString(),
        );
        results[teacherId] = code;
      } catch (e) {
        results[teacherId] = 'FAILED: $e';
      }
    }
    return results;
  }

  /// Bulk approve/reject vault items
  Future<void> bulkApproveVaultItems({
    required List<int> vaultItemIds,
    required bool approved,
    String? rejectionReason,
  }) async {
    await _db.transaction(() async {
      for (final id in vaultItemIds) {
        if (approved) {
          await _db.vaultItemsDao.approve(id, DateTime.now());
        } else {
          await _db.vaultItemsDao.reject(id, rejectionReason ?? 'Rejected');
        }
      }
    });
  }
}
```

### Step 7.7: Payment Webhook Handler (Documentation)

The server-side webhook at `POST /payment/webhook` from Paystack:
1. Validates Paystack signature header (`x-paystack-signature`) using secret key SHA-512 HMAC.
2. Extracts `event.data.reference` and `event.data.status`.
3. If `status == 'success'`: updates `payment_events SET confirmed_by_webhook = true, confirmation_date = NOW()`.
4. Updates school subscription tier and expiry.
5. Updates teacher device credits (refill all device counters).
6. Client syncs within 15 minutes and receives updated credit state.

## Phase 7 Acceptance Criteria (GATE)

```bash
flutter test test/payment/paystack_test.dart              # Initialize, verify, poll
flutter test test/payment/webhook_test.dart               # Webhook signature validation
flutter test test/admin/teacher_management_test.dart       # List, detail, device list
flutter test test/admin/recovery_code_test.dart            # Generate code, offline queue
flutter test test/vault/approval_test.dart                 # Approve/reject flow
flutter test test/vault/acquire_test.dart                  # Credit spend on acquire
flutter test test/pdf/generation_test.dart                 # PDF created, watermark correct
flutter test test/pdf/cache_test.dart                      # Composite cache key works
flutter test test/export/data_export_test.dart             # CSV and JSON export
flutter test test/bulk/bulk_assign_test.dart               # Bulk subject assignment
```
```
