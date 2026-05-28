// lib/core/services/payment_service.dart
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import 'package:drift/drift.dart';
import '../database/database.dart';

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

  /// Monnify sandbox base URL.
  static const String _baseUrl = 'https://sandbox.monnify.com';

  /// Monnify test API keys — replace with actual sandbox keys from the
  /// Monnify dashboard (Settings ⇨ API Keys).
  // TODO: Replace with live Monnify keys after KYC approval
  static const String _apiKey = 'MK_TEST_ZRD477KLNN';
  static const String _secretKey = 'XYBJ75MD6WPXFUB17EAMJNRZGTXD5WCA';

  /// Default contract code — replace with the one from the Monnify sandbox
  /// dashboard (Settings ⇨ API Keys ⇨ Contract Code).
  static const String _contractCode = '1855674442';

  PaymentService(this._db, this._dio);

  // ---------------------------------------------------------------------------
  // Headers
  // ---------------------------------------------------------------------------

  Options _getOptions() {
    final credentials = base64Encode(utf8.encode('$_apiKey:$_secretKey'));
    return Options(
      headers: {
        'Authorization': 'Basic $credentials',
        'Content-Type': 'application/json',
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Initialize payment
  // ---------------------------------------------------------------------------

  /// Initialize a Monnify payment.
  /// Returns a [PaymentInitResult] with the checkout URL and transaction reference.
  Future<PaymentInitResult> initializePayment({
    required String email,
    required int amountNaira, // in NGN
    required String plan,     // 'basic', 'standard', 'elite'
    required String schoolId,
  }) async {
    final reference = _uuid.v4();
    final response = await _dio.post(
      '$_baseUrl/api/v1/merchant/transactions/init-transaction',
      data: {
        'amount': amountNaira,
        'customerName': 'School Name',
        'customerEmail': email,
        'paymentReference': reference,
        'paymentDescription': 'ClassAI $plan subscription',
        'currencyCode': 'NGN',
        'contractCode': _contractCode,
        'redirectUrl': 'classai://payment/complete',
        'paymentMethods': ['CARD', 'ACCOUNT_TRANSFER'],
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
      checkoutUrl: response.data['responseBody']['checkoutUrl'],
      reference: reference,
    );
  }

  // ---------------------------------------------------------------------------
  // Verify payment
  // ---------------------------------------------------------------------------

  /// Verify a payment with Monnify.
  Future<bool> verifyPayment(String reference) async {
    final response = await _dio.get(
      '$_baseUrl/api/v1/merchant/transactions/query',
      queryParameters: {'transactionReference': reference},
      options: _getOptions(),
    );

    final requestSuccessful =
        response.data['requestSuccessful'] as bool? ?? false;
    final responseBody =
        response.data['responseBody'] as Map<String, dynamic>?;
    final status = responseBody?['transactionStatus'] as String?;

    if (requestSuccessful && status == 'SUCCESS') {
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
