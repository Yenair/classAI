import 'package:drift/drift.dart';

class SchemeGenerationQueue extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get schoolId => integer().withDefault(const Constant(0))();
  IntColumn get subjectId => integer().withDefault(const Constant(0))();
  TextColumn get term => text().withDefault(const Constant(''))();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  TextColumn get errorMessage => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

