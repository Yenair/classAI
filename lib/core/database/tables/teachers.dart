import 'package:drift/drift.dart';

import 'schools.dart';

class Teachers extends Table {
  IntColumn get localId => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  TextColumn get email => text()();
  TextColumn get teacherName => text()();
  TextColumn get role =>
      text().withDefault(const Constant('teacher'))(); // 'teacher' or 'admin'
  IntColumn get schoolLocalId => integer().references(Schools, #localId)();
  TextColumn get schoolServerId => text().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();
  BoolColumn get forcePasswordReset =>
      boolean().withDefault(const Constant(false))();
  IntColumn get passwordHashVersion =>
      integer().withDefault(const Constant(1))();
  TextColumn get schoolKeyWrapped =>
      text().nullable()(); // base64, teacher's wrapped school key
  DateTimeColumn get lastCreditRefillDate => dateTime().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  TextColumn get salt =>
      text().nullable()(); // cached Argon2id salt from server (base64)
  TextColumn get lastModifiedBy => text().nullable()();

  // Device tracking for no concurrent sessions
  TextColumn get currentDeviceId => text().nullable()();
}
