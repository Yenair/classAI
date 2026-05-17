import 'package:drift/drift.dart';
import 'teachers.dart';
import 'subjects.dart';

/// Join table linking teachers to subjects they are assigned to.
class TeacherSubjects extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get teacherLocalId => integer().references(Teachers, #localId)();
  IntColumn get subjectId => integer().references(Subjects, #id)();
}
