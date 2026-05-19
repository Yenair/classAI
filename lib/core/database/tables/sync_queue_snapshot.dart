import 'package:drift/drift.dart';

class SyncQueueSnapshot extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get snapshotData => text()(); // JSON blob of the sync queue state
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

