// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'teacher_subjects_dao.dart';

// ignore_for_file: type=lint
mixin _$TeacherSubjectsDaoMixin on DatabaseAccessor<AppDatabase> {
  $SchoolsTable get schools => attachedDatabase.schools;
  $TeachersTable get teachers => attachedDatabase.teachers;
  $SubjectsTable get subjects => attachedDatabase.subjects;
  $TeacherSubjectsTable get teacherSubjects => attachedDatabase.teacherSubjects;
  TeacherSubjectsDaoManager get managers => TeacherSubjectsDaoManager(this);
}

class TeacherSubjectsDaoManager {
  final _$TeacherSubjectsDaoMixin _db;
  TeacherSubjectsDaoManager(this._db);
  $$SchoolsTableTableManager get schools =>
      $$SchoolsTableTableManager(_db.attachedDatabase, _db.schools);
  $$TeachersTableTableManager get teachers =>
      $$TeachersTableTableManager(_db.attachedDatabase, _db.teachers);
  $$SubjectsTableTableManager get subjects =>
      $$SubjectsTableTableManager(_db.attachedDatabase, _db.subjects);
  $$TeacherSubjectsTableTableManager get teacherSubjects =>
      $$TeacherSubjectsTableTableManager(
          _db.attachedDatabase, _db.teacherSubjects);
}
