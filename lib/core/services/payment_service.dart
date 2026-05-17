// lib/core/services/payment_service.dart
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import '../database/database.dart';

class PaymentService {
  final AppDatabase _db;
  final Dio _dio;
  final _uuid = const Uuid();

  PaymentService(this._db, this._dio);

  /// Initialize a Paystack payment.
  /// Returns a Paystack checkout URL to open in WebView.
  Future<String> initializePayment({
    required String email,
    required int amountNaira, // in NGN
    required String plan,     // 'basic', 'standard', 'elite'
    required String schoolId,
  }) async {
    final reference = _uuid.v4();
    final response = await _dio.post(
      '/payment/initialize',
      data: {
        'email': email,
        'amount': amountNaira * 100, // Paystack uses kobo
        'reference': reference,
        'plan': plan,
        'school_id': schoolId,
        'currency': 'NGN',
      },
    );

    // Save pending payment event locally
    await _db.paymentEventsDao.insert(
      transactionReference: reference,
      confirmedByWebhook: false,
      amount: amountNaira,
      plan: plan,
      createdAt: DateTime.now(),
    );

    return response.data['authorization_url'];
  }

  /// Verify a payment with Paystack.
  Future<bool> verifyPayment(String reference) async {
    final response = await _dio.get('/payment/verify/$reference');
    final status = response.data['status'];
    if (status == 'success') {
      await _db.paymentEventsDao.markConfirmed(reference);
      return true;
    }
    return false;
  }

  /// Poll for payment confirmation (called after WebView closes).
  /// Polls every 30 seconds for up to 5 minutes.
  Stream<bool> pollForConfirmation(String reference) async* {
    for (int i = 0; i < 10; i++) {
      yield await verifyPayment(reference);
      await Future.delayed(const Duration(seconds: 30));
    }
  }
}
