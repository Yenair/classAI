import 'package:drift/drift.dart';

class Exams extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  TextColumn get subject => text()();
  TextColumn get classLevel => text()();
  TextColumn get topic => text()();
  TextColumn get difficulty => text()();
  TextColumn get curriculum => text()();
  TextColumn get content => text()(); // encrypted JSON (mcqs + theory)
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get lastModifiedBy => text().nullable()();
}
