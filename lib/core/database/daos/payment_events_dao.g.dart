// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'payment_events_dao.dart';

// ignore_for_file: type=lint
mixin _$PaymentEventsDaoMixin on DatabaseAccessor<AppDatabase> {
  $PaymentEventsTable get paymentEvents => attachedDatabase.paymentEvents;
  PaymentEventsDaoManager get managers => PaymentEventsDaoManager(this);
}

class PaymentEventsDaoManager {
  final _$PaymentEventsDaoMixin _db;
  PaymentEventsDaoManager(this._db);
  $$PaymentEventsTableTableManager get paymentEvents =>
      $$PaymentEventsTableTableManager(_db.attachedDatabase, _db.paymentEvents);
}
