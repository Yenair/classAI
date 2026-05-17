// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'schools_dao.dart';

// ignore_for_file: type=lint
mixin _$SchoolsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchoolsTable get schools => attachedDatabase.schools;
  SchoolsDaoManager get managers => SchoolsDaoManager(this);
}

class SchoolsDaoManager {
  final _$SchoolsDaoMixin _db;
  SchoolsDaoManager(this._db);
  $$SchoolsTableTableManager get schools =>
      $$SchoolsTableTableManager(_db.attachedDatabase, _db.schools);
}
