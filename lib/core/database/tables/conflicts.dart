import 'package:drift/drift.dart';

class Conflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordType => text()();
  IntColumn get recordLocalId => integer()();
  TextColumn get conflictingFields => text()(); // JSON array
  TextColumn get resolution => text().withDefault(const Constant('unresolved'))();
  BoolColumn get notified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

