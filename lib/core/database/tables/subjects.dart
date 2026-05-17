import 'package:drift/drift.dart';

class Subjects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  TextColumn get name => text()();
  TextColumn get alias => text().nullable()(); // for duplicate detection via manifest aliases
  TextColumn get schoolId => text().nullable()(); // server school ID
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
