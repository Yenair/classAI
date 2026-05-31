// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'scheme_of_work_dao.dart';

// ignore_for_file: type=lint
mixin _$SchemeOfWorkDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchemeOfWorkTable get schemeOfWork => attachedDatabase.schemeOfWork;
  SchemeOfWorkDaoManager get managers => SchemeOfWorkDaoManager(this);
}

class SchemeOfWorkDaoManager {
  final _$SchemeOfWorkDaoMixin _db;
  SchemeOfWorkDaoManager(this._db);
  $$SchemeOfWorkTableTableManager get schemeOfWork =>
      $$SchemeOfWorkTableTableManager(_db.attachedDatabase, _db.schemeOfWork);
}
