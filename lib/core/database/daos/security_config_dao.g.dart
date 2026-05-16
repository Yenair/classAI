// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'security_config_dao.dart';

// ignore_for_file: type=lint
mixin _$SecurityConfigDaoMixin on DatabaseAccessor<AppDatabase> {
  $SecurityConfigTable get securityConfig => attachedDatabase.securityConfig;
  SecurityConfigDaoManager get managers => SecurityConfigDaoManager(this);
}

class SecurityConfigDaoManager {
  final _$SecurityConfigDaoMixin _db;
  SecurityConfigDaoManager(this._db);
  $$SecurityConfigTableTableManager get securityConfig =>
      $$SecurityConfigTableTableManager(
          _db.attachedDatabase, _db.securityConfig);
}
