import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/sync_queue.dart';

part 'sync_queue_dao.g.dart';

@DriftAccessor(tables: [SyncQueue])
class SyncQueueDao extends DatabaseAccessor<AppDatabase>
    with _$SyncQueueDaoMixin {
  SyncQueueDao(AppDatabase db) : super(db);

  Future<void> insertEntry({
    required String queueTable  ,
    required int recordLocalId,
    required String operation,
    required Map<String, dynamic> payload,
    int attempts = 0,
    bool isEmergency = false,
  }) async {
    await into(syncQueue).insert(
      SyncQueueCompanion.insert(
        queueTable : queueTable  ,
        recordLocalId: recordLocalId,
        operation: operation,
        payload: payload.toString(),
        attempts:Value(attempts),
        isEmergency: Value(isEmergency),
      ),
    );
  }
}