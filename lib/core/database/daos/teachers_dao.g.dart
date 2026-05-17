// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'teachers_dao.dart';

// ignore_for_file: type=lint
mixin _$TeachersDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchoolsTable get schools => attachedDatabase.schools;
  $TeachersTable get teachers => attachedDatabase.teachers;
  TeachersDaoManager get managers => TeachersDaoManager(this);
}

class TeachersDaoManager {
  final _$TeachersDaoMixin _db;
  TeachersDaoManager(this._db);
  $$SchoolsTableTableManager get schools =>
      $$SchoolsTableTableManager(_db.attachedDatabase, _db.schools);
  $$TeachersTableTableManager get teachers =>
      $$TeachersTableTableManager(_db.attachedDatabase, _db.teachers);
}
