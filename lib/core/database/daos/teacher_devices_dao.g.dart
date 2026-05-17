// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'teacher_devices_dao.dart';

// ignore_for_file: type=lint
mixin _$TeacherDevicesDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchoolsTable get schools => attachedDatabase.schools;
  $TeachersTable get teachers => attachedDatabase.teachers;
  $TeacherDevicesTable get teacherDevices => attachedDatabase.teacherDevices;
  TeacherDevicesDaoManager get managers => TeacherDevicesDaoManager(this);
}

class TeacherDevicesDaoManager {
  final _$TeacherDevicesDaoMixin _db;
  TeacherDevicesDaoManager(this._db);
  $$SchoolsTableTableManager get schools =>
      $$SchoolsTableTableManager(_db.attachedDatabase, _db.schools);
  $$TeachersTableTableManager get teachers =>
      $$TeachersTableTableManager(_db.attachedDatabase, _db.teachers);
  $$TeacherDevicesTableTableManager get teacherDevices =>
      $$TeacherDevicesTableTableManager(
          _db.attachedDatabase, _db.teacherDevices);
}
