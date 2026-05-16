import 'package:drift/drift.dart';

class SyncQueueSnapshot extends Table {
  IntColumn get id => integer().autoIncrement()();
}

