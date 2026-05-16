import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/emergency_flush_service.dart';

void main() {
  group('EmergencyFlushService', () {
    late EmergencyFlushService service;

    setUp(() {
      service = EmergencyFlushService();
    });

    test('register adds a callback', () async {
      bool called = false;
      service.register(() async {
        called = true;
      });

      await service.flushAll();
      expect(called, isTrue);
    });

    test('flushAll calls all registered callbacks', () async {
      int callCount = 0;

      service.register(() async {
        callCount++;
      });
      service.register(() async {
        callCount++;
      });
      service.register(() async {
        callCount++;
      });

      await service.flushAll();
      expect(callCount, equals(3));
    });

    test('flushAll clears callbacks after execution', () async {
      int callCount = 0;
      service.register(() async {
        callCount++;
      });

      await service.flushAll();
      expect(callCount, equals(1));

      // Second flush should not call the original callback
      await service.flushAll();
      expect(callCount, equals(1));
    });

    test('unregister removes a callback', () async {
      int callCount = 0;

      Future<void> callback() async {
        callCount++;
      }

      service.register(callback);
      service.register(callback);

      service.unregister(callback);

      await service.flushAll();
      // Only the second registration should fire
      expect(callCount, equals(1));
    });

    test('error in one callback does not prevent others from running', () async {
      int callCount = 0;

      service.register(() async {
        throw Exception('Callback 1 failed');
      });
      service.register(() async {
        callCount++;
      });
      service.register(() async {
        callCount++;
      });

      // Should not throw
      await service.flushAll();
      expect(callCount, equals(2));
    });

    test('flushAll with no callbacks completes silently', () async {
      // Should not throw
      await service.flushAll();
      // Should still be in valid state
      expect(true, isTrue);
    });
  });
}
