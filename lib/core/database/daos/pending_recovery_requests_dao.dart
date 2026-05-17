// lib/core/database/daos/pending_recovery_requests_dao.dart
import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/pending_recovery_requests.dart';

part 'pending_recovery_requests_dao.g.dart';

@DriftAccessor(tables: [PendingRecoveryRequests])
class PendingRecoveryRequestsDao extends DatabaseAccessor<AppDatabase>
    with _$PendingRecoveryRequestsDaoMixin {
  PendingRecoveryRequestsDao(AppDatabase db) : super(db);

  /// Queue a recovery code request for when the device comes online.
  Future<int> queueRequest({
    required int teacherLocalId,
    required String requestedByAdminId,
  }) async {
    return into(pendingRecoveryRequests).insert(
      PendingRecoveryRequestsCompanion.insert(
        teacherLocalId: teacherLocalId,
        requestedByAdminId: requestedByAdminId,
      ),
    );
  }

  /// Get all unfulfilled recovery requests.
  Future<List<PendingRecoveryRequest>> getPending() {
    return (select(pendingRecoveryRequests)
          ..where((t) => t.fulfilled.equals(false))
          ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
        .get();
  }

  /// Mark a request as fulfilled with the generated code and expiry.
  Future<void> markFulfilled(
    int requestId, {
    required String generatedCode,
    required DateTime codeExpiry,
  }) async {
    await (update(pendingRecoveryRequests)
          ..where((t) => t.id.equals(requestId)))
        .write(
      PendingRecoveryRequestsCompanion(
        fulfilled: const Value(true),
        generatedCode: Value(generatedCode),
        codeExpiry: Value(codeExpiry),
        processedAt: Value(DateTime.now()),
      ),
    );
  }
}
