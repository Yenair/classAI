// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'terms_dao.dart';

// ignore_for_file: type=lint
mixin _$TermsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchoolsTable get schools => attachedDatabase.schools;
  $TermsTable get terms => attachedDatabase.terms;
  TermsDaoManager get managers => TermsDaoManager(this);
}

class TermsDaoManager {
  final _$TermsDaoMixin _db;
  TermsDaoManager(this._db);
  $$SchoolsTableTableManager get schools =>
      $$SchoolsTableTableManager(_db.attachedDatabase, _db.schools);
  $$TermsTableTableManager get terms =>
      $$TermsTableTableManager(_db.attachedDatabase, _db.terms);
}
