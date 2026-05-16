import 'package:drift/drift.dart';

class Lessons extends Table {
  IntColumn get id => integer().autoIncrement()();
}
