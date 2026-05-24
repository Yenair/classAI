import 'package:drift/drift.dart';

class AuditLogs extends Table {
  TextColumn get id => text().withDefault(const Constant(''))();
  TextColumn get teacherId => text().nullable()();
  TextColumn get schoolId => text().nullable()();
  TextColumn get action => text().withDefault(const Constant(''))();
  TextColumn get metadata => text().nullable()(); // JSON stored as text
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
