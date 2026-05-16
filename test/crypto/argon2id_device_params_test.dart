// test/crypto/argon2id_device_params_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/utils/encryption_utils.dart';

void main() {
  group('ArgonParams.forDevice', () {
    test('returns valid device‑adaptive parameters', () async {
      final params = await ArgonParams.forDevice();

      // Must return a non‑null, sensible set of values
      expect(params.memory, greaterThan(0));
      expect(params.iterations, greaterThan(0));
      expect(params.parallelism, greaterThan(0));
      expect(params.saltLength, equals(32));
    });

    test('default fallback is moderate (desktop/test environment)', () async {
      // In test environments, device_info_plus typically throws,
      // so we expect the fallback params (32768 KB memory, 3 iterations, 2 parallelism)
      final params = await ArgonParams.forDevice();
      // The fallback should be the moderate setting
      expect(params.memory, 32768);
      expect(params.iterations, 3);
      expect(params.parallelism, 2);
      expect(params.saltLength, 32);
    });
  });
}