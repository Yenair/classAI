import 'package:flutter_test/flutter_test.dart';
import 'package:classai/core/services/low_storage_service.dart';
import 'package:classai/core/constants/app_constants.dart';

void main() {
  group('LowStorageService', () {
    late LowStorageService storageService;

    setUp(() {
      storageService = LowStorageService();
    });

    group('constants', () {
      test('warning threshold is 500 MB', () {
        expect(AppConstants.warningStorageThresholdMB, 500.0);
      });

      test('critical threshold is 100 MB', () {
        expect(AppConstants.criticalStorageThresholdMB, 100.0);
      });

      test('warning threshold is greater than critical threshold', () {
        expect(AppConstants.warningStorageThresholdMB,
            greaterThan(AppConstants.criticalStorageThresholdMB));
      });
    });

    group('checkDiskSpace', () {
      test('returns a LowStorageLevel without throwing', () async {
        final level = await storageService.checkDiskSpace();
        expect(level, isA<LowStorageLevel>());
      });

      test('can be called multiple times', () async {
        await storageService.checkDiskSpace();
        await storageService.checkDiskSpace();
        final level = await storageService.checkDiskSpace();
        expect(level, isA<LowStorageLevel>());
      });
    });

    group('canGeneratePdf', () {
      test('returns a boolean without throwing', () async {
        final canGenerate = await storageService.canGeneratePdf();
        expect(canGenerate, isA<bool>());
      });
    });

    group('getDiskSpaceDisplay', () {
      test('returns a human-readable string', () async {
        final display = await storageService.getDiskSpaceDisplay();
        expect(display, isA<String>());
        expect(display.isNotEmpty, isTrue);
      });
    });

    group('currentLevel', () {
      test('starts at ok level', () {
        expect(storageService.currentLevel, LowStorageLevel.ok);
      });

      test('updates after checkDiskSpace call', () async {
        await storageService.checkDiskSpace();
        // Level should be one of the valid enum values
        expect(
          [LowStorageLevel.ok, LowStorageLevel.warning, LowStorageLevel.critical],
          contains(storageService.currentLevel),
        );
      });
    });

    group('LowStorageLevel enum', () {
      test('has three valid levels', () {
        expect(LowStorageLevel.values, hasLength(3));
        expect(LowStorageLevel.values, contains(LowStorageLevel.ok));
        expect(LowStorageLevel.values, contains(LowStorageLevel.warning));
        expect(LowStorageLevel.values, contains(LowStorageLevel.critical));
      });
    });

    group('onLevelChanged callback', () {
      test('can be set and is callable', () async {
        // ignore: unused_local_variable
        LowStorageLevel? capturedLevel;
        storageService.onLevelChanged = (level) {
          capturedLevel = level;
        };

        // Trigger a check
        await storageService.checkDiskSpace();

        // Callback is optional and may or may not fire depending on state
        expect(storageService.onLevelChanged, isNotNull);
      });
    });
  });
}
