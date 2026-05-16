import 'package:drift/drift.dart';

class PendingRecoveryRequests extends Table {
  IntColumn get id => integer().autoIncrement()();
}

