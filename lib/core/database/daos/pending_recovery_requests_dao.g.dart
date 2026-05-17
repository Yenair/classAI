// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pending_recovery_requests_dao.dart';

// ignore_for_file: type=lint
mixin _$PendingRecoveryRequestsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchoolsTable get schools => attachedDatabase.schools;
  $TeachersTable get teachers => attachedDatabase.teachers;
  $PendingRecoveryRequestsTable get pendingRecoveryRequests =>
      attachedDatabase.pendingRecoveryRequests;
  PendingRecoveryRequestsDaoManager get managers =>
      PendingRecoveryRequestsDaoManager(this);
}

class PendingRecoveryRequestsDaoManager {
  final _$PendingRecoveryRequestsDaoMixin _db;
  PendingRecoveryRequestsDaoManager(this._db);
  $$SchoolsTableTableManager get schools =>
      $$SchoolsTableTableManager(_db.attachedDatabase, _db.schools);
  $$TeachersTableTableManager get teachers =>
      $$TeachersTableTableManager(_db.attachedDatabase, _db.teachers);
  $$PendingRecoveryRequestsTableTableManager get pendingRecoveryRequests =>
      $$PendingRecoveryRequestsTableTableManager(
          _db.attachedDatabase, _db.pendingRecoveryRequests);
}
