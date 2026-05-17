// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'exams_dao.dart';

// ignore_for_file: type=lint
mixin _$ExamsDaoMixin on DatabaseAccessor<AppDatabase> {
  $ExamsTable get exams => attachedDatabase.exams;
  ExamsDaoManager get managers => ExamsDaoManager(this);
}

class ExamsDaoManager {
  final _$ExamsDaoMixin _db;
  ExamsDaoManager(this._db);
  $$ExamsTableTableManager get exams =>
      $$ExamsTableTableManager(_db.attachedDatabase, _db.exams);
}
