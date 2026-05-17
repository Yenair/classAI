// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress_logs_dao.dart';

// ignore_for_file: type=lint
mixin _$ProgressLogsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ProgressLogsTable get progressLogs => attachedDatabase.progressLogs;
  ProgressLogsDaoManager get managers => ProgressLogsDaoManager(this);
}

class ProgressLogsDaoManager {
  final _$ProgressLogsDaoMixin _db;
  ProgressLogsDaoManager(this._db);
  $$ProgressLogsTableTableManager get progressLogs =>
      $$ProgressLogsTableTableManager(_db.attachedDatabase, _db.progressLogs);
}
