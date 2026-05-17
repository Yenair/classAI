import 'package:drift/drift.dart';
import 'teachers.dart';

/// Tracks devices registered to each teacher for admin management.
class TeacherDevices extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teacherId => integer().references(Teachers, #localId)();
  TextColumn get deviceId => text()();
  TextColumn get deviceName => text()();
  TextColumn get platform => text()(); // 'android', 'ios', 'web', 'windows', 'macos', 'linux'
  TextColumn get lastActive => text().nullable()(); // ISO-8601 timestamp
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
