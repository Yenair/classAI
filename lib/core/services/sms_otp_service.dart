import 'package:dio/dio.dart';
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
  final String senderId; // e.g., "ClassAI"
  final String baseUrl;

  const SmsProviderConfig({
    required this.apiKey,
    required this.senderId,
    this.baseUrl = 'https://api.termii.com/api',
  });
}

/// SMS OTP service using Termii (primary) or BulkSMS Nigeria (fallback).
///
/// Provides SMS-based OTP delivery as an alternative to email OTP for:
/// - Account activation
/// - Password recovery
/// - Admin recovery
///
/// This is critical for Nigerian schools where SMS is more reliable than email.
///
/// ## Provider Support
/// - **Termii**: Primary provider. Uses Termii's SMS API with OTP messaging.
/// - **BulkSMS Nigeria**: Automatic fallback if Termii fails.
class SmsOtpService {
  final Dio _dio;
  final SmsProviderConfig _config;

  SmsOtpService(this._dio, this._config);

  /// Send an OTP code via SMS using Termii.
  ///
  /// [phoneNumber] should be in international format (e.g., "+2348012345678").
  /// Returns [SmsOtpResult] indicating whether the SMS was sent.
  Future<SmsOtpResult> sendOtpViaTermii({
    required String phoneNumber,
    String? messageTemplate,
  }) async {
    try {
      final otp = _generateOtp();
      final message = messageTemplate ?? 'Your ClassAI verification code is: $otp';

      final response = await _dio.post(
        '${_config.baseUrl}/api/sms/otp/send',
        data: {
          'api_key': _config.apiKey,
          'message_type': 'NUMERIC',
          'to': phoneNumber,
          'from': _config.senderId,
          'channel': 'generic',
          'pin_attempts': 3,
          'pin_time_to_live': 10, // minutes
          'pin_length': 6,
          'pin_placeholder': '<pin>',
          'message_text': message,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final sent = data['status'] == 'success' || data['sent'] == true;
      final expiryMinutes = data['pin_time_to_live'] as int? ?? 10;

      return SmsOtpResult(
        sent: sent,
        otpExpiry: sent
            ? DateTime.now().add(Duration(minutes: expiryMinutes))
            : null,
        message: sent ? 'OTP sent to $phoneNumber' : 'Failed to send OTP',
      );
    } on DioException catch (e) {
      debugPrint('SMS OTP via Termii failed: $e');
      // Fallback to BulkSMS Nigeria
      return sendOtpViaBulkSmsNigeria(
        phoneNumber: phoneNumber,
        messageTemplate: messageTemplate,
      );
    } catch (e) {
      debugPrint('SMS OTP via Termii failed with unexpected error: $e');
      return const SmsOtpResult(
        sent: false,
        message: 'Failed to send OTP via SMS',
      );
    }
  }

  /// Send an OTP via BulkSMS Nigeria (fallback provider).
  ///
  /// Used when Termii is unavailable.
  Future<SmsOtpResult> sendOtpViaBulkSmsNigeria({
    required String phoneNumber,
    String? messageTemplate,
  }) async {
    try {
      final otp = _generateOtp();
      final message = messageTemplate ?? 'Your ClassAI verification code is: $otp';

      // BulkSMS Nigeria API format
      final response = await _dio.post(
        'https://www.bulksmsnigeria.com/api/v1/sms/create',
        data: {
          'api_token': _config.apiKey,
          'from': _config.senderId,
          'to': phoneNumber,
          'body': message,
          'dnd': 2, // route through DND-compliant channel
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final sent = data['status'] == 'success' || data['data']?['status'] == 'success';

      return SmsOtpResult(
        sent: sent,
        otpExpiry: sent ? DateTime.now().add(const Duration(minutes: 10)) : null,
        message: sent ? 'OTP sent to $phoneNumber' : 'Failed to send OTP',
      );
    } catch (e) {
      debugPrint('SMS OTP via BulkSMS Nigeria failed: $e');
      return const SmsOtpResult(
        sent: false,
        message: 'All SMS providers unavailable',
      );
    }
  }

  /// Verify an OTP code via Termii.
  ///
  /// [pinId] is returned from the send call.
  /// [otp] is the user-provided code.
  Future<bool> verifyOtpViaTermii({
    required String pinId,
    required String otp,
  }) async {
    try {
      final response = await _dio.post(
        '${_config.baseUrl}/api/sms/otp/verify',
        data: {
          'api_key': _config.apiKey,
          'pin_id': pinId,
          'pin': otp,
        },
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      return data['status'] == 'success' && data['verified'] == true;
    } catch (e) {
      debugPrint('OTP verification via Termii failed: $e');
      return false;
    }
  }

  /// Generate a 6-digit numeric OTP.
  String _generateOtp() {
    final random = DateTime.now().microsecondsSinceEpoch;
    final otp = (random % 900000 + 100000).toString();
    return otp;
  }
}
