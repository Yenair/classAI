import 'package:drift/drift.dart';
import '../database.dart';
import '../tables/payment_events.dart';

part 'payment_events_dao.g.dart';

@DriftAccessor(tables: [PaymentEvents])
class PaymentEventsDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentEventsDaoMixin {
  PaymentEventsDao(AppDatabase db) : super(db);

  Future<int> insert({
    required String transactionReference,
    required bool confirmedByWebhook,
    required int amount,
    required String plan,
    required DateTime createdAt,
  }) async {
    final id = await into(paymentEvents).insert(
      PaymentEventsCompanion.insert(
        transactionReference: transactionReference,
        confirmedByWebhook: Value(confirmedByWebhook),
        amount: amount,
        plan: plan,
        createdAt: Value(createdAt),
      ),
    );
    try {
      final school = await db.schoolsDao.get();
      await db.syncQueueDao.insertEntry(
        queueTable: 'payment_events',
        recordLocalId: id,
        operation: 'INSERT',
        payload: {
          'transaction_reference': transactionReference,
          'confirmed_by_webhook': confirmedByWebhook,
          'amount': amount,
          'plan': plan,
          'school_server_id': school?.serverId,
        },
      );
    } catch (_) {
      // Non-critical — payment event sync failure shouldn't block
    }
    return id;
  }

  Future<List<PaymentEvent>> getUnconfirmed() {
    return (select(paymentEvents)
          ..where((t) => t.confirmedByWebhook.equals(false))
          ..orderBy([
            (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
          ]))
        .get();
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
