import 'package:drift/drift.dart';

class Conflicts extends Table {
  IntColumn get id => integer().autoIncrement()();
}

