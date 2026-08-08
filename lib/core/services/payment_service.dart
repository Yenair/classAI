// lib/core/services/payment_service.dart
import 'package:supabase_flutter/supabase_flutter.dart' as supabase_pkg;
import '../database/database.dart';
import 'auth_service.dart';

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

  PaymentService(this._db);

  /// The Supabase client for invoking Edge Functions.
  supabase_pkg.SupabaseClient get _client =>
      supabase_pkg.Supabase.instance.client;

  String _requireAdminJwt(String action) {
    final jwt = SupabaseAuthService().currentJwt;
    if (jwt == null || jwt.isEmpty) {
      throw Exception('Admin not authenticated - cannot $action payment');
    }
    return jwt;
  }

  // ---------------------------------------------------------------------------
  // Initialize payment
  // ---------------------------------------------------------------------------

  /// Initialize a Paystack payment via the [init-payment] Edge Function.
  /// Returns a [PaymentInitResult] with the authorization URL and transaction reference.
  Future<PaymentInitResult> initializePayment({
    required String email,
    required int amountNaira, // in NGN
    required String plan,     // 'basic', 'standard', 'elite'
    required String schoolId,
  }) async {
    final jwt = _requireAdminJwt('initialize');
    final response = await _client.functions.invoke(
      'init-payment',
      headers: {
        'x-classai-jwt': jwt,
      },
      body: {
        'email': email,
        'amount': amountNaira,
        'plan': plan,
        'school_id': schoolId,
      },
    );

    final data = response.data as Map<String, dynamic>;

    final reference = data['reference'] as String;

    // Persist the pending transaction locally before opening checkout.
    await _db.paymentEventsDao.insert(
      transactionReference: reference,
      confirmedByWebhook: false,
      amount: amountNaira,
      plan: plan,
      createdAt: DateTime.now(),
    );

    return PaymentInitResult(
      checkoutUrl: data['authorization_url'] as String,
      reference: reference,
    );
  }

  // ---------------------------------------------------------------------------
  // Verify payment
  // ---------------------------------------------------------------------------

  /// Verify a payment via the [verify-payment] Edge Function.
  Future<bool> verifyPayment(String reference) async {
    final jwt = _requireAdminJwt('verify');
    final response = await _client.functions.invoke(
      'verify-payment',
      headers: {
        'x-classai-jwt': jwt,
      },
      body: {
        'reference': reference,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final status = data['status'] as String?;

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

  /// Confirm a successful payment by calling the [confirm-payment] Edge Function.
  ///
  /// The Edge Function verifies the transaction server-to-server with Paystack,
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
    final response = await _client.functions.invoke(
      'confirm-payment',
      headers: {
        'x-classai-jwt': _requireAdminJwt('confirm'),
      },
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

    // ── M3: Fetch authoritative school record from Supabase ─────────────────
    // The schoolId comes from the authenticated school's server UUID
    // (sourced from JWT claims / auth provider, not from the confirm-payment
    // response). This reduces — but does not eliminate — the blank-name window:
    // a fallback path still exists for network or timeout failures.
    String schoolName = '';
    String shortCode = '';
    String activeCurriculum = 'nerdc';
    int totalSeats = 5;

    try {
      final schoolData = await _client
          .from('schools')
          .select('*')
          .eq('id', schoolId)
          .single()
          .timeout(const Duration(seconds: 5));
      schoolName = schoolData['school_name'] as String? ?? schoolName;
      shortCode = schoolData['short_code'] as String? ?? shortCode;
      activeCurriculum =
          schoolData['active_curriculum'] as String? ?? activeCurriculum;
      totalSeats = schoolData['total_seats'] as int? ?? totalSeats;
    } catch (fetchError) {
      // School-fetch query failed or timed out. Fall back gracefully with
      // the best available data (tier and expiry from confirm-payment).
      // The school name/ shortCode will be blank only as a last resort.
      // This is logged for debugging.
      // ignore: avoid_print
      print('[payment_service] failed to fetch school after payment: $fetchError');
    }

    // Use the canonical upsert DAO which preserves existing fields
    // and correctly handles the insert-vs-update path.
    await _db.schoolsDao.upsertByServerId(
      serverId: schoolId,
      schoolName: schoolName,
      shortCode: shortCode,
      subscriptionTier: subscriptionTier,
      activeCurriculum: activeCurriculum,
      totalSeats: totalSeats,
      expiryDate: expiryDate,
      activationCode: activationCode,
    );

    return PaymentConfirmation(
      activationCode: activationCode,
      subscriptionTier: subscriptionTier,
      expiryDate: expiryDate,
    );
  }
}
