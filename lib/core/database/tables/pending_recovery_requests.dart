import 'package:drift/drift.dart';
import 'teachers.dart';

/// Tracks admin-generated recovery code requests that are queued for
/// processing when the device comes online.
class PendingRecoveryRequests extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teacherLocalId => integer().references(Teachers, #localId)();
  TextColumn get requestedByAdminId => text()(); // server ID of requesting admin
  BoolColumn get fulfilled => boolean().withDefault(const Constant(false))();
  TextColumn get generatedCode => text().nullable()(); // 16-char code, set when processed
  DateTimeColumn get codeExpiry => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get processedAt => dateTime().nullable()();
  TextColumn get email => text()(); // teacher email for rate-limiting lookups
  DateTimeColumn get attemptedAt => dateTime()(); // timestamp of the recovery attempt
}
