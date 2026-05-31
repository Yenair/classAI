import 'package:drift/drift.dart';

class ProgressLogs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  TextColumn get eventType => text()();
  IntColumn get lessonId => integer().withDefault(const Constant(0))();
  IntColumn get teacherId => integer().withDefault(const Constant(0))();
  IntColumn get schoolId => integer().withDefault(const Constant(0))();
  DateTimeColumn get eventDate => dateTime().withDefault(currentDateAndTime)();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
