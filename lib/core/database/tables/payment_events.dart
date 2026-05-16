// lib/core/database/tables/payment_events.dart
import 'package:drift/drift.dart';

class PaymentEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get transactionReference => text()();
  BoolColumn get confirmedByWebhook => boolean().withDefault(const Constant(false))();
  IntColumn get amount => integer()(); // in Naira
  TextColumn get plan => text()(); // 'basic', 'standard', 'elite'
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get confirmationDate => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}