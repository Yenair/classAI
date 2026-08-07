import 'package:drift/drift.dart';

class FieldConflictHistory extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordTable => text()();
  IntColumn get recordLocalId => integer()();
  TextColumn get fieldName => text()();
  TextColumn get discardedValueJson => text()();
  TextColumn get winningValueJson => text()();
  DateTimeColumn get localUpdatedAt => dateTime().nullable()();
  DateTimeColumn get remoteUpdatedAt => dateTime().nullable()();
  DateTimeColumn get recordedAt => dateTime().withDefault(currentDateAndTime)();
}
