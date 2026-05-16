import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/deep_link_service.dart';

void main() {
  group('DeepLinkService.parse', () {
    test('parses reset-password deep link with token', () {
      final result = DeepLinkService.parse(
        'classai://reset-password?token=abc123',
      );

      expect(result, isNotNull);
      expect(result!.type, equals(DeepLinkType.resetPassword));
      expect(result.token, equals('abc123'));
    });

    test('parses activate deep link with code', () {
      final result = DeepLinkService.parse(
        'classai://activate?code=ACTIVATE1',
      );

      expect(result, isNotNull);
      expect(result!.type, equals(DeepLinkType.activate));
      expect(result.code, equals('ACTIVATE1'));
    });

    test('parses admin-recovery deep link with token', () {
      final result = DeepLinkService.parse(
        'classai://admin-recovery?token=admin_recovery_token',
      );

      expect(result, isNotNull);
      expect(result!.type, equals(DeepLinkType.adminRecovery));
      expect(result.token, equals('admin_recovery_token'));
    });

    test('returns null for non-classai scheme', () {
      final result = DeepLinkService.parse(
        'https://example.com/reset-password?token=abc',
      );

      expect(result, isNull);
    });

    test('returns null for unknown deep link host', () {
      final result = DeepLinkService.parse(
        'classai://unknown-path?param=value',
      );

      expect(result, isNull);
    });

    test('returns null for reset-password without token', () {
      final result = DeepLinkService.parse(
        'classai://reset-password',
      );

      expect(result, isNull);
    });

    test('returns null for activate without code', () {
      final result = DeepLinkService.parse(
        'classai://activate',
      );

      expect(result, isNull);
    });

    test('returns null for admin-recovery without token', () {
      final result = DeepLinkService.parse(
        'classai://admin-recovery',
      );

      expect(result, isNull);
    });

    test('returns null for empty string', () {
      final result = DeepLinkService.parse('');

      expect(result, isNull);
    });

    test('returns null for malformed URI', () {
      final result = DeepLinkService.parse('not a uri at all');

      expect(result, isNull);
    });

    test('handles multiple query parameters gracefully', () {
      final result = DeepLinkService.parse(
        'classai://reset-password?token=abc&extra=value',
      );

      expect(result, isNotNull);
      expect(result!.type, equals(DeepLinkType.resetPassword));
      expect(result.token, equals('abc'));
      // Extra parameters are kept in queryParameters map
      expect(result.queryParameters['extra'], equals('value'));
    });
  });
}
