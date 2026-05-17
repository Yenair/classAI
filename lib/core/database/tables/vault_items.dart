// lib/core/database/tables/vault_items.dart
import 'package:drift/drift.dart';

class VaultItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get serverId => text().nullable()();
  TextColumn get title => text()();
  TextColumn get description => text()();
  TextColumn get subject => text()();
  TextColumn get classLevel => text()();
  TextColumn get curriculum => text()();
  TextColumn get content => text()(); // JSON
  TextColumn get authorTeacherId => text()(); // server ID
  TextColumn get authorName => text()();
  TextColumn get minTier => text().withDefault(const Constant('free'))();
  IntColumn get creditCost => integer().withDefault(const Constant(0))();
  BoolColumn get needsApproval => boolean().withDefault(const Constant(true))();
  TextColumn get approvalStatus => text().withDefault(const Constant('pending'))(); // 'pending', 'approved', 'rejected'
  TextColumn get rejectionReason => text().nullable()();
  TextColumn get thumbnailUrl => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  IntColumn get updateCounter => integer().withDefault(const Constant(0))();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();
  DateTimeColumn get acquisitionDate => dateTime().nullable()();
  TextColumn get creditSpentBatchId => text().nullable()();

}
