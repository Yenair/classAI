import 'package:drift/drift.dart';

class VersionHashes extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get table => text().named('table_name')();       // e.g., 'lessons', 'exams'
  IntColumn get recordLocalId => integer()();
  TextColumn get hash => text()();            // SHA-256 of record state at last sync
  DateTimeColumn get setAt => dateTime()();
}
