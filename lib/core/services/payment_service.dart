// lib/core/services/payment_service.dart
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import 'package:drift/drift.dart';
import '../database/database.dart';
import '../constants/paystack_keys.dart';

/// Result returned by [PaymentService.initializePayment].
class PaymentInitResult {
  final String checkoutUrl;
  final String reference;

  PaymentInitResult({required this.checkoutUrl, required this.reference});
}

/// Result returned by [PaymentService.confirmPayment].
class PaymentConfirmation {
  final String activationCode;
  final String subscriptionTier;
  final DateTime expiryDate;

  PaymentConfirmation({
    required this.activationCode,
    required this.subscriptionTier,
    required this.expiryDate,
  });
}

class PaymentService {
  final AppDatabase _db;
  final Dio _dio;
  final _uuid = const Uuid();

  /// Paystack base URL.
  static const String _baseUrl = 'https://api.paystack.co';

  /// Paystack secret key loaded from [paystack_keys.dart].
  static const String _secretKey = paystackSecretKey;

  PaymentService(this._db, this._dio);

  // ---------------------------------------------------------------------------
  // Headers
  // ---------------------------------------------------------------------------

  Options _getOptions() {
    return Options(
      headers: {
        'Authorization': 'Bearer $_secretKey',
        'Content-Type': 'application/json',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Initialize payment
  // ---------------------------------------------------------------------------

  /// Initialize a Paystack payment.
  /// Returns a [PaymentInitResult] with the authorization URL and transaction reference.
  Future<PaymentInitResult> initializePayment({
    required String email,
    required int amountNaira, // in NGN
    required String plan,     // 'basic', 'standard', 'elite'
    required String schoolId,
  }) async {
    final reference = _uuid.v4();
    final amountKobo = amountNaira * 100; // Paystack expects amount in kobo
    final response = await _dio.post(
      '$_baseUrl/transaction/initialize',
      data: {
        'email': email,
        'amount': amountKobo,
        'reference': reference,
        'currency': 'NGN',
        'callback_url': 'classai://payment/complete',
      },
      options: _getOptions(),
    );

    // Save pending payment event locally
    await _db.paymentEventsDao.insert(
      transactionReference: reference,
      confirmedByWebhook: false,
      amount: amountNaira,
      plan: plan,
      createdAt: DateTime.now(),
    );

    return PaymentInitResult(
      checkoutUrl: response.data['data']['authorization_url'],
      reference: reference,
    );
  }

  // ---------------------------------------------------------------------------
  // Verify payment
  // ---------------------------------------------------------------------------

  /// Verify a payment with Paystack.
  Future<bool> verifyPayment(String reference) async {
    final response = await _dio.get(
      '$_baseUrl/transaction/verify/$reference',
      options: _getOptions(),
    );

    final data = response.data['data'] as Map<String, dynamic>?;
    final status = data?['status'] as String?;

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

  /// Confirm a successful payment by calling the confirm-payment Edge Function.
  ///
  /// The Edge Function verifies the transaction with Monnify server-to-server,
  /// generates an activation code, and updates the school's subscription tier
  /// and expiry date in Supabase.
  ///
  /// Returns a [PaymentConfirmation] with the activation code.
  /// On failure, throws an [Exception] with details.
  Future<PaymentConfirmation> confirmPayment({
    required String reference,
    required String plan,
    required String schoolId,
  }) async {
    final client = supabase_pkg.Supabase.instance.client;
    final response = await client.functions.invoke(
      'confirm-payment',
      body: {
        'reference': reference,
        'plan': plan,
        'school_id': schoolId,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final errorResponse = data['error'] as String?;
    if (errorResponse != null) {
      throw Exception(errorResponse);
    }

    final activationCode = data['activation_code'] as String;
    final subscriptionTier = data['subscription_tier'] as String;
    final expiryDateStr = data['expiry_date'] as String;
    final expiryDate = DateTime.parse(expiryDateStr);

    // Update the local school record with the new data
    await _db.into(_db.schools).insert(
      SchoolsCompanion.insert(
        serverId: Value(schoolId),
        schoolName: '', // placeholder; will be filled by sync
        shortCode: '',
        subscriptionTier: Value(subscriptionTier),
        expiryDate: Value(expiryDate),
        activationCode: Value(activationCode),
      ),
      mode: InsertMode.insertOrReplace,
    );

    return PaymentConfirmation(
      activationCode: activationCode,
      subscriptionTier: subscriptionTier,
      expiryDate: expiryDate,
    );
  }
}
