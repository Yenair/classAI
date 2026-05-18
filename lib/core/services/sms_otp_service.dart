import 'package:flutter/foundation.dart';

/// Result of an SMS OTP request.
class SmsOtpResult {
  final bool sent;
  final DateTime? otpExpiry;
  final String? message;

  const SmsOtpResult({
    required this.sent,
    this.otpExpiry,
    this.message,
  });
}

/// Configuration for SMS provider.
class SmsProviderConfig {
  final String apiKey;
  final String senderId;
  final String baseUrl;

  const SmsProviderConfig({
    required this.apiKey,
    required this.senderId,
    this.baseUrl = 'https://api.termii.com/api',
  });
}

/// SMS OTP service — currently stubbed.
///
/// SMS OTP functionality has been temporarily disabled.
/// All methods return placeholder values. Restore the full
/// implementation when SMS OTP is re-enabled.
class SmsOtpService {
  SmsOtpService(this._dio, this._config);

  // ignore: unused_field
  final dynamic _dio;
  // ignore: unused_field
  final SmsProviderConfig _config;

  /// Stubbed — returns [SmsOtpResult] with `sent: false`.
  Future<SmsOtpResult> sendOtpViaTermii({
    required String phoneNumber,
    String? messageTemplate,
  }) async {
    debugPrint('[STUB] sendOtpViaTermii called for $phoneNumber');
    return const SmsOtpResult(
      sent: false,
      message: 'SMS OTP is currently unavailable',
    );
  }

  /// Stubbed — returns [SmsOtpResult] with `sent: false`.
  Future<SmsOtpResult> sendOtpViaBulkSmsNigeria({
    required String phoneNumber,
    String? messageTemplate,
  }) async {
    debugPrint('[STUB] sendOtpViaBulkSmsNigeria called for $phoneNumber');
    return const SmsOtpResult(
      sent: false,
      message: 'SMS OTP is currently unavailable',
    );
  }

  /// Stubbed — returns `false`.
  Future<bool> verifyOtpViaTermii({
    required String pinId,
    required String otp,
  }) async {
    debugPrint('[STUB] verifyOtpViaTermii called');
    return false;
  }
}
