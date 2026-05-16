import 'package:drift/drift.dart';

class VaultItems extends Table {
  IntColumn get id => integer().autoIncrement()();
}
