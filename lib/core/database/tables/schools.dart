import 'package:drift/drift.dart';

class Schools extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()(); // UUID from server
  TextColumn get schoolName => text()();
  TextColumn get shortCode => text()();
  TextColumn get logoUrl => text().nullable()();
  TextColumn get subscriptionTier => text().withDefault(const Constant('free'))();
  TextColumn get activeCurriculum => text().withDefault(const Constant('nerdc'))();
  TextColumn get activeCurriculumVersion => text().nullable()();
  IntColumn get totalSeats => integer().withDefault(const Constant(5))();
  TextColumn get schoolMasterKeyWrapped => text().nullable()(); // base64
  TextColumn get adminRecoveryEmail => text().nullable()();
  BoolColumn get adminRecoveryEmailVerified => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get expiryDate => dateTime().nullable()();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get activationCode => text().nullable()();
  TextColumn get lastModifiedBy => text().nullable()(); // teacher_id for sync

}
