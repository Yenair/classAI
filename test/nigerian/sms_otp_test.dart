import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/sms_otp_service.dart';
import 'package:dio/dio.dart';

void main() {
  group('SmsOtpService', () {
    setUp(() {
      // Service is instantiated inline in each test group
    });

    group('SmsProviderConfig', () {
      test('uses Termii base URL by default', () {
        const config = SmsProviderConfig(
          apiKey: 'test_key',
          senderId: 'ClassAI',
        );

        expect(config.baseUrl, 'https://api.termii.com/api');
        expect(config.apiKey, 'test_key');
        expect(config.senderId, 'ClassAI');
      });

      test('allows custom base URL for BulkSMS Nigeria', () {
        const config = SmsProviderConfig(
          apiKey: 'test_key',
          senderId: 'ClassAI',
          baseUrl: 'https://www.bulksmsnigeria.com/api/v1',
        );

        expect(config.baseUrl, 'https://www.bulksmsnigeria.com/api/v1');
      });
    });

    group('SmsOtpResult', () {
      test('creates a sent result correctly', () {
        const result = SmsOtpResult(
          sent: true,
          otpExpiry: null,
          message: 'OTP sent successfully',
        );

        expect(result.sent, isTrue);
        expect(result.otpExpiry, isNull);
        expect(result.message, 'OTP sent successfully');
      });

      test('creates a failed result with nullable expiry', () {
        const result = SmsOtpResult(
          sent: false,
          otpExpiry: null,
          message: 'Failed to send OTP',
        );

        expect(result.sent, isFalse);
        expect(result.otpExpiry, isNull);
        expect(result.message, 'Failed to send OTP');
      });

      test('allows non-null otpExpiry', () {
        final expiry = DateTime.now().add(const Duration(minutes: 5));
        final result = SmsOtpResult(
          sent: true,
          otpExpiry: expiry,
          message: 'OTP sent successfully',
        );

        expect(result.sent, isTrue);
        expect(result.otpExpiry, equals(expiry));
      });
    });

    group('sendOtpViaTermii', () {
      test('returns SmsOtpResult when Termii is unreachable', () async {
        // Using an invalid base URL should cause a DioException,
        // which triggers the BulkSMS Nigeria fallback (also unreachable).
        // The final catch block returns SmsOtpResult(sent: false).
        final localService = SmsOtpService(
          Dio(BaseOptions(
            baseUrl: 'https://invalid.nonexistent.api',
            connectTimeout: const Duration(milliseconds: 100),
            receiveTimeout: const Duration(milliseconds: 100),
          )),
          const SmsProviderConfig(
            apiKey: 'test_key',
            senderId: 'ClassAI',
          ),
        );

        final result = await localService.sendOtpViaTermii(
          phoneNumber: '+2348012345678',
        );

        expect(result, isA<SmsOtpResult>());
        expect(result.sent, isFalse);
      }, timeout: const Timeout(Duration(seconds: 10)));
    });
  });
}
