// lib/core/database/tables/sync_queue.dart
import 'package:drift/drift.dart';

class SyncQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get queueTable  => text()();
  IntColumn get recordLocalId => integer()();
  TextColumn get operation => text()(); // INSERT, UPDATE, DELETE, SPEND_CREDITS
  TextColumn get payload => text()(); // JSON
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  BoolColumn get isEmergency => boolean().withDefault(const Constant(false))();
  BoolColumn get isTerminal => boolean().withDefault(const Constant(false))();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get failedAt => dateTime().nullable()();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get lastAttemptAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
