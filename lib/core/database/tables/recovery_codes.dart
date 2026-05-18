import 'package:drift/drift.dart';
import 'teachers.dart';

class RecoveryCodes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get phoneNumber => text()();
  TextColumn get code => text()();
  DateTimeColumn get expiresAt => dateTime()();
  BoolColumn get used => boolean().withDefault(const Constant(false))();
  IntColumn get teacherLocalId => integer().references(Teachers, #localId)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
