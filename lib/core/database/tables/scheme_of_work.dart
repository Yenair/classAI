import 'package:drift/drift.dart';

class SchemeOfWork extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  IntColumn get schoolId => integer().withDefault(const Constant(0))();
  IntColumn get teacherId => integer().withDefault(const Constant(0))();
  IntColumn get subjectId => integer().withDefault(const Constant(0))();
  TextColumn get term => text().withDefault(const Constant(''))();
  IntColumn get weekNumber => integer().withDefault(const Constant(1))();
  TextColumn get topic => text().withDefault(const Constant(''))();
  TextColumn get objectives => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('draft'))();
  TextColumn get adminEditedTopic => text().nullable()();
  TextColumn get adminComment => text().nullable()();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get classLevel => text().withDefault(const Constant(''))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
