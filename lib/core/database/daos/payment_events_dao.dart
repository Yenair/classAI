import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/payment_events.dart';

part 'payment_events_dao.g.dart';

@DriftAccessor(tables: [PaymentEvents])
class PaymentEventsDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentEventsDaoMixin {
  PaymentEventsDao(AppDatabase db) : super(db);

  Future<void> insert({
    required String transactionReference,
    required bool confirmedByWebhook,
    required int amount,
    required String plan,
    required DateTime createdAt,
  }) async {
    await into(paymentEvents).insert(
      PaymentEventsCompanion.insert(
        transactionReference: transactionReference,
        confirmedByWebhook: Value(confirmedByWebhook),
        amount: amount,
        plan: plan,
        createdAt: Value(createdAt),
      ),
    );
  }

  Future<void> markConfirmed(String reference) async {
    await (update(paymentEvents)
          ..where((t) => t.transactionReference.equals(reference)))
        .write(
      const PaymentEventsCompanion(
        confirmedByWebhook: Value(true),
      ),
    );
  }
}