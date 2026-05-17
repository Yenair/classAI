import 'package:drift/drift.dart';

class Lessons extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get subject => text()();
  TextColumn get classLevel => text()();
  IntColumn get week => integer()();
  TextColumn get topic => text()();
  TextColumn get difficulty => text()();
  TextColumn get bloomsVerbs => text()();
  TextColumn get curriculum => text()();
  TextColumn get content => text()(); // encrypted JSON
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
