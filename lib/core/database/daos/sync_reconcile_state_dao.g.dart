// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sync_reconcile_state_dao.dart';

// ignore_for_file: type=lint
mixin _$SyncReconcileStateDaoMixin on DatabaseAccessor<AppDatabase> {
  $SyncReconcileStateTable get syncReconcileState =>
      attachedDatabase.syncReconcileState;
  SyncReconcileStateDaoManager get managers =>
      SyncReconcileStateDaoManager(this);
}

class SyncReconcileStateDaoManager {
  final _$SyncReconcileStateDaoMixin _db;
  SyncReconcileStateDaoManager(this._db);
  $$SyncReconcileStateTableTableManager get syncReconcileState =>
      $$SyncReconcileStateTableTableManager(
          _db.attachedDatabase, _db.syncReconcileState);
}
